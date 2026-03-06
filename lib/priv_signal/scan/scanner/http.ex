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
    provenance = build_provenance(function_def.body, inventory)

    {_node, findings} =
      Macro.prewalk(function_def.body, [], fn node, acc ->
        case sink_from_call(node, additional_modules) do
          nil ->
            {node, acc}

          sink ->
            evidence =
              node
              |> call_args()
              |> Enum.flat_map(&collect_arg_evidence(&1, inventory, provenance))
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

  defp build_provenance(nil, _inventory), do: %{}

  defp build_provenance(body, inventory) do
    {_node, assignments} =
      Macro.prewalk(body, %{}, fn node, acc ->
        case node do
          {:=, _, [lhs, rhs]} ->
            case local_var(lhs) do
              nil ->
                {node, acc}

              var_name ->
                evidence = Evidence.collect(rhs, inventory)
                deps = local_vars(rhs)
                {node, Map.put(acc, var_name, %{evidence: evidence, deps: deps})}
            end

          _ ->
            {node, acc}
        end
      end)

    assignments
  end

  defp collect_arg_evidence(arg, inventory, provenance) do
    direct = Evidence.collect(arg, inventory)
    vars = [local_var(arg) | local_vars(arg)] |> Enum.reject(&is_nil/1) |> Enum.uniq()

    {resolved_evidence, lineage} =
      Enum.reduce(vars, {direct, []}, fn var_name, {ev_acc, chain_acc} ->
        {resolved, chain} = resolve_var(var_name, provenance, MapSet.new(), [var_name], 0)
        {Evidence.dedupe(ev_acc ++ resolved), chain ++ chain_acc}
      end)

    fields = Evidence.matched_nodes(resolved_evidence)

    indirect =
      if fields == [] or vars == [] do
        []
      else
        [
          %PrivSignal.Scan.Evidence{
            type: :indirect_payload_ref,
            expression:
              "payload_lineage:" <>
                Enum.map_join(Enum.reverse(Enum.uniq(lineage)), "->", &Atom.to_string/1),
            fields: fields,
            match_source: strongest_match_source(resolved_evidence),
            lineage: Enum.map(Enum.uniq(lineage), &Atom.to_string/1)
          }
        ]
      end

    resolved_evidence ++ indirect
  end

  defp resolve_var(_var_name, _provenance, _visited, lineage, depth) when depth > 6 do
    {[], lineage}
  end

  defp resolve_var(var_name, provenance, visited, lineage, depth) do
    if MapSet.member?(visited, var_name) do
      {[], lineage}
    else
      entry = Map.get(provenance, var_name, %{evidence: [], deps: []})
      visited = MapSet.put(visited, var_name)

      {dep_evidence, dep_lineage} =
        Enum.reduce(entry.deps, {[], lineage}, fn dep, {ev_acc, lineage_acc} ->
          {dep_ev, dep_line} =
            resolve_var(dep, provenance, visited, [dep | lineage_acc], depth + 1)

          {dep_ev ++ ev_acc, dep_line}
        end)

      {Evidence.dedupe(entry.evidence ++ dep_evidence), dep_lineage}
    end
  end

  defp local_vars(ast) do
    {_ast, vars} =
      Macro.prewalk(ast, MapSet.new(), fn node, acc ->
        case local_var(node) do
          nil -> {node, acc}
          name -> {node, MapSet.put(acc, name)}
        end
      end)

    MapSet.to_list(vars)
  end

  defp local_var({name, _, context}) when is_atom(name) and is_atom(context), do: name
  defp local_var(_), do: nil

  defp strongest_match_source(evidence_entries) do
    evidence_entries
    |> Enum.map(&Map.get(&1, :match_source))
    |> Enum.reject(&is_nil/1)
    |> Enum.min_by(&source_rank/1, fn -> :normalized end)
  end

  defp source_rank(:exact), do: 0
  defp source_rank(:normalized), do: 1
  defp source_rank(:alias), do: 2
  defp source_rank(_), do: 3
end
