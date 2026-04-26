defmodule PrivSignal.Scan.Scanner.Database do
  @moduledoc """
  Detects privacy-relevant data read from or written to database calls.
  """

  @behaviour PrivSignal.Scan.Scanner

  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Scan.Scanner.Evidence
  alias PrivSignal.Scan.Scanner.Utils

  @read_calls [:get, :get_by, :one, :all, :preload]
  @write_calls [:insert, :update, :delete, :insert_all, :update_all, :delete_all]

  @impl true
  def scan_ast(ast, %{path: path} = file_ctx, %Inventory{} = inventory, opts) do
    scanner_cfg = database_config(opts)

    if scanner_cfg.enabled do
      module_functions = module_functions(ast, file_ctx)
      repo_modules = MapSet.new(Enum.map(scanner_cfg.repo_modules, &to_string/1))
      summaries = build_function_summaries(module_functions, repo_modules)
      wrapper_modules = wrapper_modules(scanner_cfg, module_functions)

      module_functions
      |> Enum.flat_map(fn module_entry ->
        Enum.flat_map(module_entry.functions, fn function_def ->
          scan_function(
            path,
            module_entry.module,
            function_def,
            inventory,
            repo_modules,
            summaries,
            wrapper_modules,
            scanner_cfg
          )
        end)
      end)
      |> Utils.stable_sort_candidates()
    else
      []
    end
  end

  defp scan_function(
         path,
         module_name,
         function_def,
         inventory,
         repo_modules,
         summaries,
         wrapper_modules,
         scanner_cfg
       ) do
    {_node, findings} =
      Macro.prewalk(function_def.body, [], fn node, acc ->
        findings_for_node =
          case repo_call_kind(node, repo_modules) do
            nil ->
              wrapper_call_kinds(
                node,
                module_name,
                summaries,
                wrapper_modules,
                scanner_cfg.wrapper_functions
              )

            {kind, sink} ->
              [{kind, sink, :direct}]
          end

        if findings_for_node == [] do
          {node, acc}
        else
          evidence =
            node
            |> call_args()
            |> Enum.flat_map(&Evidence.collect(&1, inventory))
            |> Evidence.dedupe()

          new_findings =
            Enum.map(findings_for_node, fn {kind, sink, source_type} ->
              wrapper_evidence =
                case source_type do
                  :wrapper ->
                    [
                      %PrivSignal.Scan.Evidence{
                        type: :inherited_db_wrapper,
                        expression: sink,
                        fields: Evidence.matched_nodes(evidence),
                        match_source: :exact
                      }
                    ]

                  _ ->
                    []
                end

              merged_evidence =
                (evidence ++ wrapper_evidence)
                |> Evidence.dedupe()

              %{
                module: module_name,
                function: function_def.name,
                arity: function_def.arity,
                file: path,
                line: sink_line(node),
                sink: sink,
                matched_nodes: Evidence.matched_nodes(merged_evidence),
                evidence: merged_evidence,
                role_kind: kind,
                node_type_hint: if(kind == "database_read", do: "source", else: "sink"),
                role_subtype: if(source_type == :wrapper, do: "wrapper", else: nil),
                boundary: "internal"
              }
            end)

          {node, new_findings ++ acc}
        end
      end)

    Enum.reverse(findings)
  end

  defp repo_call_kind({{:., _, [target, method]}, _, _args}, repo_modules)
       when is_atom(method) do
    target_name = Utils.module_name(target)

    if repo_target?(target, target_name, repo_modules) do
      cond do
        method in @read_calls -> {"database_read", "Repo.#{method}"}
        method in @write_calls -> {"database_write", "Repo.#{method}"}
        true -> nil
      end
    else
      nil
    end
  end

  defp repo_call_kind(_, _), do: nil

  defp wrapper_call_kinds(
         node,
         current_module,
         summaries,
         wrapper_modules,
         wrapper_functions
       ) do
    case wrapper_target(node, current_module) do
      nil ->
        []

      {target_module, function_name, arity} ->
        if wrapper_allowed?(
             target_module,
             function_name,
             arity,
             wrapper_modules,
             wrapper_functions
           ) do
          summary =
            Map.get(summaries, {target_module, function_name, arity}, %{
              read?: false,
              write?: false
            })

          []
          |> maybe_add_wrapper_kind(
            summary.read?,
            "database_read",
            target_module,
            function_name,
            arity
          )
          |> maybe_add_wrapper_kind(
            summary.write?,
            "database_write",
            target_module,
            function_name,
            arity
          )
        else
          []
        end
    end
  end

  defp maybe_add_wrapper_kind(acc, false, _kind, _mod, _fun, _arity), do: acc

  defp maybe_add_wrapper_kind(acc, true, kind, target_module, function_name, arity) do
    sink = "Wrapper.#{target_module}.#{function_name}/#{arity}"
    [{kind, sink, :wrapper} | acc]
  end

  defp wrapper_target({name, _, args}, current_module) when is_atom(name) and is_list(args) do
    {current_module, Atom.to_string(name), length(args)}
  end

  defp wrapper_target({{:., _, [target, name]}, _, args}, _current_module)
       when is_atom(name) and is_list(args) do
    target_module = Utils.module_name(target)

    if is_binary(target_module) do
      {target_module, Atom.to_string(name), length(args)}
    else
      nil
    end
  end

  defp wrapper_target(_, _), do: nil

  defp wrapper_allowed?(target_module, function_name, arity, wrapper_modules, wrapper_functions) do
    module_allowed = MapSet.member?(wrapper_modules, target_module)

    function_allowed =
      case wrapper_functions do
        [] ->
          true

        values ->
          signature = "#{function_name}/#{arity}"
          Enum.member?(values, function_name) or Enum.member?(values, signature)
      end

    module_allowed and function_allowed
  end

  defp repo_target?({name, _, _}, _target_name, _repo_modules) when name == :repo, do: true

  defp repo_target?(_target, target_name, repo_modules) when is_binary(target_name) do
    String.ends_with?(target_name, "Repo") or MapSet.member?(repo_modules, target_name)
  end

  defp repo_target?(_, _, _), do: false

  defp module_functions(ast, file_ctx) do
    file_ctx
    |> Map.get(:cache, %{})
    |> Map.get(:module_functions)
    |> case do
      list when is_list(list) -> list
      _ -> Utils.extract_module_functions(ast)
    end
  end

  defp build_function_summaries(module_functions, repo_modules) do
    Enum.reduce(module_functions, %{}, fn module_entry, acc ->
      Enum.reduce(module_entry.functions, acc, fn function_def, module_acc ->
        {read?, write?} = function_repo_usage(function_def.body, repo_modules)

        if read? or write? do
          Map.put(module_acc, {module_entry.module, function_def.name, function_def.arity}, %{
            read?: read?,
            write?: write?
          })
        else
          module_acc
        end
      end)
    end)
  end

  defp function_repo_usage(nil, _repo_modules), do: {false, false}

  defp function_repo_usage(body, repo_modules) do
    {_node, state} =
      Macro.prewalk(body, %{read?: false, write?: false}, fn node, acc ->
        case repo_call_kind(node, repo_modules) do
          {"database_read", _sink} ->
            {node, %{acc | read?: true}}

          {"database_write", _sink} ->
            {node, %{acc | write?: true}}

          _ ->
            {node, acc}
        end
      end)

    {state.read?, state.write?}
  end

  defp wrapper_modules(scanner_cfg, module_functions) do
    configured =
      scanner_cfg.wrapper_modules
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    discovered =
      module_functions
      |> Enum.map(& &1.module)
      |> MapSet.new()

    MapSet.union(configured, discovered)
  end

  defp call_args({{:., _, _}, _, args}) when is_list(args), do: args
  defp call_args(_), do: []

  defp sink_line({_, meta, _}), do: Utils.meta_line(meta)
  defp sink_line(_), do: nil

  defp database_config(opts) do
    scanners = opts[:scanner_config] || PrivSignal.Config.default_scanners()
    scanners.database || %PrivSignal.Config.Scanners.Database{}
  end
end
