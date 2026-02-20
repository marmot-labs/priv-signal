defmodule PrivSignal.Scan.Scanner.Database do
  @moduledoc false

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

      module_functions
      |> Enum.flat_map(fn module_entry ->
        Enum.flat_map(module_entry.functions, fn function_def ->
          scan_function(path, module_entry.module, function_def, inventory, repo_modules)
        end)
      end)
      |> Utils.stable_sort_candidates()
    else
      []
    end
  end

  defp scan_function(path, module_name, function_def, inventory, repo_modules) do
    {_node, findings} =
      Macro.prewalk(function_def.body, [], fn node, acc ->
        case repo_call_kind(node, repo_modules) do
          nil ->
            {node, acc}

          {kind, sink} ->
            evidence =
              node
              |> call_args()
              |> Enum.flat_map(&Evidence.collect(&1, inventory))
              |> Evidence.dedupe()

            finding = %{
              module: module_name,
              function: function_def.name,
              arity: function_def.arity,
              file: path,
              line: sink_line(node),
              sink: sink,
              matched_nodes: Evidence.matched_nodes(evidence),
              matched_fields: Evidence.matched_nodes(evidence),
              evidence: evidence,
              role_kind: kind,
              node_type_hint: if(kind == "database_read", do: "source", else: "sink"),
              boundary: "internal"
            }

            {node, [finding | acc]}
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

  defp call_args({{:., _, _}, _, args}) when is_list(args), do: args
  defp call_args(_), do: []

  defp sink_line({_, meta, _}), do: Utils.meta_line(meta)
  defp sink_line(_), do: nil

  defp database_config(opts) do
    scanners = opts[:scanner_config] || PrivSignal.Config.default_scanners()
    scanners.database || %PrivSignal.Config.Scanners.Database{}
  end
end
