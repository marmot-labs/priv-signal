defmodule PrivSignal.Scan.Scanner.HTTP do
  @moduledoc false

  @behaviour PrivSignal.Scan.Scanner

  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Scan.Scanner.Evidence
  alias PrivSignal.Scan.Scanner.Utils

  @http_modules ["Finch", "Tesla", "HTTPoison", "Req", "Mint.HTTP", "HTTPotion"]
  @erlang_modules [:hackney, :httpc]
  @http_methods ["get", "post", "put", "patch", "delete", "request", "build", "stream"]

  @impl true
  def scan_ast(ast, %{path: path} = file_ctx, %Inventory{} = inventory, opts) do
    scanner_cfg = http_config(opts)

    if scanner_cfg.enabled do
      module_functions = module_functions(ast, file_ctx)

      additional_modules =
        scanner_cfg.additional_modules |> Enum.map(&normalize_module/1) |> MapSet.new()

      module_functions
      |> Enum.flat_map(fn module_entry ->
        Enum.flat_map(module_entry.functions, fn function_def ->
          scan_function(
            path,
            module_entry.module,
            function_def,
            inventory,
            scanner_cfg,
            additional_modules
          )
        end)
      end)
      |> Utils.stable_sort_candidates()
    else
      []
    end
  end

  defp scan_function(path, module_name, function_def, inventory, scanner_cfg, additional_modules) do
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

            matched_nodes = Evidence.matched_nodes(evidence)
            line = sink_line(node)
            {boundary, confidence} = boundary_for_call(node, scanner_cfg)

            finding = %{
              module: module_name,
              function: function_def.name,
              arity: function_def.arity,
              file: path,
              line: line,
              sink: sink,
              matched_nodes: matched_nodes,
              evidence: evidence,
              role_kind: "http",
              boundary: boundary,
              confidence_hint: confidence
            }

            {node, [finding | acc]}
        end
      end)

    Enum.reverse(findings)
  end

  defp sink_from_call({{:., _, [target, method]}, _, _args}, additional_modules)
       when is_atom(method) do
    normalized_method = normalize_method(method)

    cond do
      normalized_method in @http_methods and http_module?(target) ->
        "#{Utils.module_name(target)}.#{normalized_method}"

      normalized_method in @http_methods and additional_http_module?(target, additional_modules) ->
        "#{Utils.module_name(target)}.#{normalized_method}"

      normalized_method in @http_methods and erlang_http_module?(target) ->
        "#{inspect(target)}.#{normalized_method}"

      true ->
        nil
    end
  end

  defp sink_from_call(_node, _additional_modules), do: nil

  defp http_module?(target) do
    module_name = normalize_module(Utils.module_name(target))
    module_name in @http_modules
  end

  defp additional_http_module?(target, additional_modules) do
    module_name = normalize_module(Utils.module_name(target))
    MapSet.member?(additional_modules, module_name)
  end

  defp erlang_http_module?(target) when target in @erlang_modules, do: true
  defp erlang_http_module?(_), do: false

  defp boundary_for_call(node, scanner_cfg) do
    host = extract_host(node)
    internal = scanner_cfg.internal_domains |> Enum.map(&String.downcase/1) |> MapSet.new()
    external = scanner_cfg.external_domains |> Enum.map(&String.downcase/1) |> MapSet.new()

    case host do
      nil ->
        {"external", 0.5}

      host ->
        host = String.downcase(host)

        cond do
          MapSet.member?(external, host) -> {"external", 1.0}
          MapSet.member?(internal, host) -> {"internal", 1.0}
          host in ["localhost", "127.0.0.1"] -> {"internal", 0.9}
          true -> {"external", 0.8}
        end
    end
  end

  defp extract_host(node) do
    node
    |> call_args()
    |> Enum.find_value(fn arg ->
      case arg do
        url when is_binary(url) ->
          case URI.parse(url) do
            %URI{host: host} when is_binary(host) and host != "" -> host
            _ -> nil
          end

        _ ->
          nil
      end
    end)
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
  defp call_args(_), do: []

  defp sink_line({_, meta, _}), do: Utils.meta_line(meta)
  defp sink_line(_), do: nil

  defp http_config(opts) do
    scanners = opts[:scanner_config] || PrivSignal.Config.default_scanners()
    scanners.http || %PrivSignal.Config.Scanners.HTTP{}
  end

  defp normalize_module(nil), do: nil

  defp normalize_module(module) do
    module
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_method(method) when is_atom(method) do
    method
    |> Atom.to_string()
    |> String.trim_trailing("!")
  end
end
