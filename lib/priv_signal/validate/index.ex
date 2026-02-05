defmodule PrivSignal.Validate.Index do
  @moduledoc false

  alias PrivSignal.Validate.AST
  require Logger

  defstruct modules: MapSet.new(),
            functions: %{},
            calls: %{},
            ambiguous_calls: %{}

  @doc """
  Builds a deterministic index of modules, functions, and call edges so validation can compare
  declared flows to source without executing code.
  """
  def build(opts \\ []) do
    # Capture timing up front so we can emit telemetry for CI diagnostics.
    start = System.monotonic_time()
    {files, errors} = source_files(opts)

    Logger.debug("[priv_signal] validate index: scanning files=#{length(files)}")

    {module_infos, parse_errors} =
      Enum.reduce(files, {[], []}, fn file, {infos, errs} ->
        case AST.parse_file(file) do
          {:ok, ast} ->
            modules =
              ast
              |> AST.extract_modules()
              |> Enum.map(fn module_info ->
                forms = AST.module_forms(module_info.body)
                Map.put(module_info, :forms, forms)
              end)

            {infos ++ modules, errs}

          {:error, reason} ->
            {infos, [reason | errs]}
        end
      end)

    errors = Enum.reverse(errors ++ parse_errors)

    result =
      if errors != [] do
        {:error, errors}
      else
        {:ok, build_index(module_infos)}
      end

    log_index_result(result)
    emit_index_telemetry(result, start, length(files))

    result
  end

  defp build_index(module_infos) do
    {modules, functions} = build_modules_functions(module_infos)
    {calls, ambiguous_calls} = build_calls(module_infos, functions)

    %__MODULE__{
      modules: modules,
      functions: functions,
      calls: calls,
      ambiguous_calls: ambiguous_calls
    }
  end

  defp log_index_result({:ok, index}) do
    # Log high-level counts to keep diagnostics useful without exposing source contents.
    counts = index_counts(index)

    Logger.info(
      "[priv_signal] validate index built modules=#{counts.module_count} functions=#{counts.function_count} calls=#{counts.call_count}"
    )

    if counts.ambiguous_count > 0 do
      Logger.warning(
        "[priv_signal] validate index ambiguous_calls=#{counts.ambiguous_count} (imports may be ambiguous)"
      )
    end
  end

  defp log_index_result({:error, errors}) do
    # Emit a concise failure summary so callers can spot parse issues quickly.
    Logger.error("[priv_signal] validate index failed errors=#{length(errors)}")
  end

  defp emit_index_telemetry({:ok, index}, start, file_count) do
    # Telemetry mirrors log counts so CI can track performance regressions.
    counts = index_counts(index)

    PrivSignal.Telemetry.emit(
      [:priv_signal, :validate, :index],
      %{duration_ms: duration_ms(start)},
      %{
        ok: true,
        file_count: file_count,
        module_count: counts.module_count,
        function_count: counts.function_count,
        call_count: counts.call_count,
        ambiguous_count: counts.ambiguous_count
      }
    )
  end

  defp emit_index_telemetry({:error, errors}, start, file_count) do
    # Preserve failure counts without leaking error details into telemetry.
    PrivSignal.Telemetry.emit(
      [:priv_signal, :validate, :index],
      %{duration_ms: duration_ms(start)},
      %{ok: false, file_count: file_count, error_count: length(errors)}
    )
  end

  defp index_counts(%__MODULE__{} = index) do
    # Summarize index sizes for telemetry and logs without leaking source details.
    module_count = MapSet.size(index.modules)

    function_count =
      index.functions
      |> Map.values()
      |> Enum.map(&MapSet.size/1)
      |> Enum.sum()

    call_count =
      index.calls
      |> Map.values()
      |> Enum.map(&MapSet.size/1)
      |> Enum.sum()

    ambiguous_count =
      index.ambiguous_calls
      |> Map.values()
      |> Enum.map(&length/1)
      |> Enum.sum()

    %{
      module_count: module_count,
      function_count: function_count,
      call_count: call_count,
      ambiguous_count: ambiguous_count
    }
  end

  defp duration_ms(start) do
    # Standardize duration reporting for telemetry consumers.
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end

  defp source_files(opts) do
    root = Keyword.get(opts, :root, project_root())
    paths = Keyword.get(opts, :paths, elixirc_paths())

    files =
      paths
      |> Enum.map(&Path.expand(&1, root))
      |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
      |> Enum.uniq()
      |> Enum.sort()

    {files, []}
  end

  defp project_root do
    case Mix.Project.project_file() do
      nil -> File.cwd!()
      path -> Path.dirname(path)
    end
  end

  defp elixirc_paths do
    Mix.Project.config()
    |> Keyword.get(:elixirc_paths, ["lib"])
  end

  defp build_modules_functions(module_infos) do
    Enum.reduce(module_infos, {MapSet.new(), %{}}, fn module_info, {modules, functions} ->
      module_name = module_info.name

      functions_for_module =
        module_info.forms
        |> AST.extract_functions()
        |> Enum.map(fn %{name: name, arity: arity} -> {Atom.to_string(name), arity} end)
        |> MapSet.new()

      {
        MapSet.put(modules, module_name),
        Map.put(functions, module_name, functions_for_module)
      }
    end)
  end

  defp build_calls(module_infos, functions) do
    Enum.reduce(module_infos, {%{}, %{}}, fn module_info, {calls, ambiguous} ->
      module_name = module_info.name
      forms = module_info.forms

      alias_map = collect_aliases(forms, module_name)
      imports = collect_imports(forms, module_name, alias_map)

      functions_defs = AST.extract_functions(forms)

      Enum.reduce(functions_defs, {calls, ambiguous}, fn %{name: name, arity: arity, body: body},
                                                         {calls_acc, amb_acc} ->
        caller_key = {module_name, Atom.to_string(name), arity}
        local_functions = Map.get(functions, module_name, MapSet.new())
        calls_in_body = AST.extract_calls(body)

        Enum.reduce(calls_in_body, {calls_acc, amb_acc}, fn call, {calls_acc2, amb_acc2} ->
          case resolve_call(call, module_name, alias_map, imports, functions, local_functions) do
            {:ok, callee} ->
              updated =
                Map.update(calls_acc2, caller_key, MapSet.new([callee]), &MapSet.put(&1, callee))

              {updated, amb_acc2}

            {:ambiguous, callee_fun, arity, candidates} ->
              entry = %{function: callee_fun, arity: arity, candidates: candidates}

              updated =
                Map.update(amb_acc2, caller_key, [entry], fn entries ->
                  [entry | entries]
                end)

              {calls_acc2, updated}

            :skip ->
              {calls_acc2, amb_acc2}
          end
        end)
      end)
    end)
  end

  defp resolve_call(
         %{type: :remote, module: module_ast, name: fun, arity: arity},
         current_module,
         alias_map,
         _imports,
         _functions,
         _local_functions
       ) do
    case resolve_module_ast(module_ast, alias_map, current_module) do
      nil -> :skip
      module_name -> {:ok, {module_name, Atom.to_string(fun), arity}}
    end
  end

  defp resolve_call(
         %{type: :local, name: fun, arity: arity},
         current_module,
         _alias_map,
         imports,
         functions,
         local_functions
       ) do
    fun_name = Atom.to_string(fun)

    cond do
      MapSet.member?(local_functions, {fun_name, arity}) ->
        {:ok, {current_module, fun_name, arity}}

      true ->
        candidates = import_candidates(fun_name, arity, imports, functions)

        case MapSet.size(candidates) do
          0 -> :skip
          1 -> {:ok, {Enum.at(candidates, 0), fun_name, arity}}
          _ -> {:ambiguous, fun_name, arity, candidates}
        end
    end
  end

  defp import_candidates(fun_name, arity, imports, functions) do
    Enum.reduce(imports, MapSet.new(), fn {module_name, specs}, acc ->
      if module_defines?(functions, module_name, fun_name, arity) and
           import_allows_any?(specs, fun_name, arity) do
        MapSet.put(acc, module_name)
      else
        acc
      end
    end)
  end

  defp module_defines?(functions, module_name, fun_name, arity) do
    case Map.get(functions, module_name) do
      nil -> false
      set -> MapSet.member?(set, {fun_name, arity})
    end
  end

  defp import_allows?(%{only: :all, except: except}, fun_name, arity) do
    not MapSet.member?(except, {fun_name, arity})
  end

  defp import_allows?(%{only: only, except: except}, fun_name, arity) do
    MapSet.member?(only, {fun_name, arity}) and not MapSet.member?(except, {fun_name, arity})
  end

  defp collect_aliases(forms, current_module) do
    Enum.reduce(forms, %{}, fn form, acc ->
      case form do
        {:alias, _meta, [alias_ast]} ->
          merge_alias(acc, alias_ast, nil, current_module)

        {:alias, _meta, [alias_ast, opts]} when is_list(opts) ->
          alias_as = Keyword.get(opts, :as)
          merge_alias(acc, alias_ast, alias_as, current_module)

        {:alias, _meta, [{{:., _meta2, [base_ast, :{}]}, _meta3, aliases}]} ->
          merge_alias_group(acc, base_ast, aliases, current_module)

        _ ->
          acc
      end
    end)
  end

  defp merge_alias(acc, alias_ast, alias_as, current_module) do
    with module_name when is_binary(module_name) <-
           resolve_module_ast(alias_ast, acc, current_module),
         alias_key when is_binary(alias_key) <- alias_key(alias_as, module_name) do
      Map.put(acc, alias_key, module_name)
    else
      _ -> acc
    end
  end

  defp merge_alias_group(acc, base_ast, aliases, current_module) when is_list(aliases) do
    base_name = resolve_module_ast(base_ast, acc, current_module)

    Enum.reduce(aliases, acc, fn alias_ast, acc2 ->
      with base_name when is_binary(base_name) <- base_name,
           alias_name when is_binary(alias_name) <-
             resolve_module_ast(alias_ast, acc2, current_module) do
        full_module = [base_name, alias_name] |> Enum.join(".")
        key = alias_key(nil, alias_name)
        Map.put(acc2, key, full_module)
      else
        _ -> acc2
      end
    end)
  end

  defp alias_key(nil, module_name) when is_binary(module_name) do
    module_name
    |> String.split(".")
    |> List.last()
  end

  defp alias_key({:__aliases__, _meta, parts}, _module_name) do
    parts
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(".")
    |> String.split(".")
    |> List.last()
  end

  defp alias_key(module, _module_name) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
  end

  defp alias_key(_other, module_name), do: alias_key(nil, module_name)

  defp collect_imports(forms, current_module, alias_map) do
    Enum.reduce(forms, %{}, fn form, acc ->
      case form do
        {:import, _meta, [module_ast]} ->
          put_import(acc, module_ast, [], current_module, alias_map)

        {:import, _meta, [module_ast, opts]} when is_list(opts) ->
          put_import(acc, module_ast, opts, current_module, alias_map)

        _ ->
          acc
      end
    end)
  end

  defp put_import(acc, module_ast, opts, current_module, alias_map) do
    case resolve_module_ast(module_ast, alias_map, current_module) do
      nil ->
        acc

      module_name ->
        Map.update(acc, module_name, [import_spec(opts)], fn specs ->
          [import_spec(opts) | specs]
        end)
    end
  end

  defp import_spec(opts) do
    only = Keyword.get(opts, :only, :all)
    except = Keyword.get(opts, :except, [])

    %{
      only: normalize_import_set(only, :all),
      except: normalize_import_set(except, MapSet.new())
    }
  end

  defp normalize_import_set(:all, fallback), do: fallback

  defp normalize_import_set(list, _fallback) when is_list(list),
    do: list |> MapSet.new() |> normalize_import_pairs()

  defp normalize_import_set(_other, fallback), do: fallback

  defp normalize_import_pairs(set) do
    Enum.reduce(set, MapSet.new(), fn
      {fun, arity}, acc when is_atom(fun) and is_integer(arity) ->
        MapSet.put(acc, {Atom.to_string(fun), arity})

      other, acc when is_tuple(other) ->
        case Tuple.to_list(other) do
          [fun, arity] when is_atom(fun) and is_integer(arity) ->
            MapSet.put(acc, {Atom.to_string(fun), arity})

          _ ->
            acc
        end

      _other, acc ->
        acc
    end)
  end

  defp import_allows_any?(specs, fun_name, arity) when is_list(specs) do
    Enum.any?(specs, &import_allows?(&1, fun_name, arity))
  end

  defp import_allows_any?(spec, fun_name, arity) do
    import_allows?(spec, fun_name, arity)
  end

  defp resolve_module_ast({:__aliases__, _meta, [:__MODULE__ | rest]}, _alias_map, current_module)
       when is_binary(current_module) do
    module = [current_module | Enum.map(rest, &Atom.to_string/1)]
    Enum.join(module, ".")
  end

  defp resolve_module_ast({:__aliases__, _meta, parts}, alias_map, _current_module)
       when is_list(parts) do
    [first | rest] = parts
    first_str = Atom.to_string(first)

    case Map.get(alias_map, first_str) do
      nil ->
        parts
        |> Enum.map(&Atom.to_string/1)
        |> Enum.join(".")

      full_module ->
        full_parts = String.split(full_module, ".")
        tail = Enum.map(rest, &Atom.to_string/1)
        Enum.join(full_parts ++ tail, ".")
    end
  end

  defp resolve_module_ast({:__MODULE__, _meta, _args}, _alias_map, current_module)
       when is_binary(current_module),
       do: current_module

  defp resolve_module_ast(module, _alias_map, _current_module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> strip_elixir_prefix()
  end

  defp resolve_module_ast(_other, _alias_map, _current_module), do: nil

  defp strip_elixir_prefix("Elixir." <> rest), do: rest
  defp strip_elixir_prefix(other), do: other
end
