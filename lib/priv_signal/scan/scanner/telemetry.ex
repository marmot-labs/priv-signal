defmodule PrivSignal.Scan.Scanner.Telemetry do
  @moduledoc false

  @behaviour PrivSignal.Scan.Scanner

  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Scan.Scanner.Evidence
  alias PrivSignal.Scan.Scanner.Utils

  @remote_calls [
    {":telemetry", :execute},
    {"Telemetry", :execute},
    {"Appsignal", :set_user},
    {"Appsignal", :add_metadata},
    {"Sentry", :capture_message},
    {"Sentry", :capture_exception},
    {"OpenTelemetry", :set_attribute},
    {"OpenTelemetry", :add_event}
  ]

  @impl true
  def scan_ast(ast, %{path: path} = file_ctx, %Inventory{} = inventory, opts) do
    scanner_cfg = telemetry_config(opts)

    if scanner_cfg.enabled do
      module_functions = module_functions(ast, file_ctx)
      additional_modules = MapSet.new(Enum.map(scanner_cfg.additional_modules, &to_string/1))

      module_functions
      |> Enum.flat_map(fn module_entry ->
        Enum.flat_map(module_entry.functions, fn function_def ->
          scan_function(path, module_entry.module, function_def, inventory, additional_modules)
        end)
      end)
      |> Utils.stable_sort_candidates()
    else
      []
    end
  end

  defp scan_function(path, module_name, function_def, inventory, additional_modules) do
    {_node, findings} =
      Macro.prewalk(function_def.body, [], fn node, acc ->
        case sink_from_call(node, additional_modules) do
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
                evidence: evidence,
                role_kind: "telemetry",
                boundary: "external"
              }

              {node, [finding | acc]}
            end
        end
      end)

    Enum.reverse(findings)
  end

  defp sink_from_call({{:., _, [target, method]}, _, _args}, additional_modules)
       when is_atom(method) do
    target_name = target_name(target)

    cond do
      {target_name, method} in @remote_calls -> "#{target_name}.#{method}"
      MapSet.member?(additional_modules, target_name) -> "#{target_name}.#{method}"
      true -> nil
    end
  end

  defp sink_from_call(_, _), do: nil

  defp target_name(atom) when is_atom(atom), do: inspect(atom)
  defp target_name(target), do: Utils.module_name(target)

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

  defp telemetry_config(opts) do
    scanners = opts[:scanner_config] || PrivSignal.Config.default_scanners()
    scanners.telemetry || %PrivSignal.Config.Scanners.Telemetry{}
  end
end
