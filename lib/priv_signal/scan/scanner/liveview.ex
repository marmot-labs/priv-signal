defmodule PrivSignal.Scan.Scanner.LiveView do
  @moduledoc false

  @behaviour PrivSignal.Scan.Scanner

  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Scan.Scanner.Evidence
  alias PrivSignal.Scan.Scanner.Utils

  @local_calls [:assign, :push_event, :render]

  @impl true
  def scan_ast(ast, %{path: path} = file_ctx, %Inventory{} = inventory, opts) do
    scanner_cfg = liveview_config(opts)

    if scanner_cfg.enabled do
      module_functions = module_functions(ast, file_ctx)

      module_functions
      |> Enum.flat_map(fn module_entry ->
        if liveview_module?(module_entry, path, file_ctx, scanner_cfg.additional_modules) do
          Enum.flat_map(module_entry.functions, fn function_def ->
            scan_function(path, module_entry.module, function_def, inventory)
          end)
        else
          []
        end
      end)
      |> Utils.stable_sort_candidates()
    else
      []
    end
  end

  defp scan_function(path, module_name, function_def, inventory) do
    {_node, findings} =
      Macro.prewalk(function_def.body, [], fn node, acc ->
        case sink_from_call(node) do
          nil ->
            {node, acc}

          sink ->
            evidence =
              node
              |> call_args()
              |> Enum.flat_map(&Evidence.collect(&1, inventory))
              |> Evidence.dedupe()

            if evidence == [] do
              {node, acc}
            else
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
                role_kind: "liveview_render",
                boundary: "external"
              }

              {node, [finding | acc]}
            end
        end
      end)

    Enum.reverse(findings)
  end

  defp sink_from_call({name, _, _args}) when is_atom(name) and name in @local_calls,
    do: Atom.to_string(name)

  defp sink_from_call(_), do: nil

  defp liveview_module?(module_entry, path, file_ctx, additional_modules) do
    module_name = module_entry.module || ""

    cache_classification =
      file_ctx
      |> Map.get(:cache, %{})
      |> Map.get(:module_classification, %{})
      |> Map.get(module_entry.module)

    String.ends_with?(module_name, "Live") or
      String.ends_with?(module_name, "LiveView") or
      String.contains?(path, "/live/") or
      cache_classification == :liveview or
      module_name in additional_modules
  end

  defp module_functions(ast, file_ctx) do
    file_ctx
    |> Map.get(:cache, %{})
    |> Map.get(:module_functions)
    |> case do
      list when is_list(list) -> list
      _ -> Utils.extract_module_functions(ast)
    end
  end

  defp call_args({_, _, args}) when is_list(args), do: args
  defp call_args(_), do: []

  defp sink_line({_, meta, _}), do: Utils.meta_line(meta)
  defp sink_line(_), do: nil

  defp liveview_config(opts) do
    scanners = opts[:scanner_config] || PrivSignal.Config.default_scanners()
    scanners.liveview || %PrivSignal.Config.Scanners.LiveView{}
  end
end
