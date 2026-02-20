defmodule PrivSignal.Scan.Scanner.Controller do
  @moduledoc false

  @behaviour PrivSignal.Scan.Scanner

  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Scan.Scanner.Evidence
  alias PrivSignal.Scan.Scanner.Utils

  @local_calls [:json, :render, :send_resp, :put_resp_body, :send_download, :send_file]
  @remote_calls [
    {"Phoenix.Controller", :json},
    {"Phoenix.Controller", :render},
    {"Plug.Conn", :send_resp},
    {"Plug.Conn", :put_resp_body},
    {"Phoenix.View", :render}
  ]

  @impl true
  def scan_ast(ast, %{path: path} = file_ctx, %Inventory{} = inventory, opts) do
    scanner_cfg = controller_config(opts)

    if scanner_cfg.enabled do
      module_functions = module_functions(ast, file_ctx)

      module_functions
      |> Enum.flat_map(fn module_entry ->
        if controller_module?(module_entry, path, file_ctx) do
          Enum.flat_map(module_entry.functions, fn function_def ->
            scan_function(path, module_entry.module, function_def, inventory, scanner_cfg)
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

  defp scan_function(path, module_name, function_def, inventory, scanner_cfg) do
    {_node, findings} =
      Macro.prewalk(function_def.body, [], fn node, acc ->
        case sink_from_call(node, scanner_cfg) do
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
                role_kind: "http_response",
                boundary: "external"
              }

              {node, [finding | acc]}
            end
        end
      end)

    Enum.reverse(findings)
  end

  defp sink_from_call({name, _, _args}, scanner_cfg) when is_atom(name) do
    cond do
      name in @local_calls ->
        Atom.to_string(name)

      additional_render_call?(name, scanner_cfg.additional_render_functions) ->
        Atom.to_string(name)

      true ->
        nil
    end
  end

  defp sink_from_call({{:., _, [target, method]}, _, _args}, scanner_cfg) when is_atom(method) do
    module_name = Utils.module_name(target)

    cond do
      {module_name, method} in @remote_calls ->
        "#{module_name}.#{method}"

      additional_render_call?("#{module_name}.#{method}", scanner_cfg.additional_render_functions) ->
        "#{module_name}.#{method}"

      true ->
        nil
    end
  end

  defp sink_from_call(_, _), do: nil

  defp additional_render_call?(call, configured_calls) do
    call in configured_calls
  end

  defp controller_module?(module_entry, path, file_ctx) do
    module_name = module_entry.module || ""

    cache_classification =
      file_ctx
      |> Map.get(:cache, %{})
      |> Map.get(:module_classification, %{})
      |> Map.get(module_entry.module)

    String.ends_with?(module_name, "Controller") or
      String.contains?(path, "/controllers/") or
      cache_classification == :controller
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

  defp call_args({{:., _, _}, _, args}) when is_list(args), do: args
  defp call_args({_, _, args}) when is_list(args), do: args
  defp call_args(_), do: []

  defp sink_line({_, meta, _}), do: Utils.meta_line(meta)
  defp sink_line(_), do: nil

  defp controller_config(opts) do
    scanners = opts[:scanner_config] || PrivSignal.Config.default_scanners()
    scanners.controller || %PrivSignal.Config.Scanners.Controller{}
  end
end
