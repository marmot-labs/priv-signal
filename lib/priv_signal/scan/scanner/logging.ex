defmodule PrivSignal.Scan.Scanner.Logging do
  @moduledoc false

  @behaviour PrivSignal.Scan.Scanner

  alias PrivSignal.Scan.Evidence
  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Scan.Scanner.Cache
  alias PrivSignal.Scan.Scanner.Utils
  alias PrivSignal.Validate.AST

  def scan_file(path, %Inventory{} = inventory, opts \\ []) do
    parse_fun = Keyword.get(opts, :parse_fun, &AST.parse_file/1)

    with {:ok, ast} <- parse_fun.(path) do
      file_cache = Cache.build(ast, path)
      {:ok, scan_ast(ast, %{path: path, cache: file_cache}, inventory, opts)}
    end
  end

  @impl true
  def scan_ast(ast, %{path: path} = file_ctx, %Inventory{} = inventory, opts) do
    scanner_cfg = logging_config(opts)

    if scanner_cfg.enabled do
      additional_modules =
        scanner_cfg.additional_modules |> Enum.map(&to_string/1) |> MapSet.new()

      module_functions = module_functions(ast, file_ctx)

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

  def scan_ast(ast, path, %Inventory{} = inventory, opts) when is_binary(path) do
    scan_ast(ast, %{path: path, cache: Cache.build(ast, path)}, inventory, opts)
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

  defp scan_function(path, module_name, function_def, inventory, additional_modules) do
    {_node, findings} =
      Macro.prewalk(function_def.body, [], fn node, acc ->
        case sink_from_call(node, additional_modules) do
          nil ->
            {node, acc}

          sink ->
            {node, add_finding(acc, path, module_name, function_def, sink, node, inventory)}
        end
      end)

    Enum.reverse(findings)
  end

  defp add_finding(acc, path, module_name, function_def, sink, sink_call_node, inventory) do
    evidence =
      sink_call_node
      |> sink_args()
      |> Enum.flat_map(&collect_evidence(&1, inventory))
      |> dedupe_evidence()

    if evidence == [] do
      acc
    else
      line = sink_line(sink_call_node)
      matched_nodes = matched_nodes(evidence)

      finding = %{
        module: module_name,
        function: function_def.name,
        arity: function_def.arity,
        file: path,
        line: line,
        sink: sink,
        matched_nodes: matched_nodes,
        evidence: evidence
      }

      [finding | acc]
    end
  end

  defp sink_from_call({{:., _, [target, method]}, _, _args}, additional_modules) do
    module_name = Utils.module_name(target)

    cond do
      logger_alias?(target) and is_atom(method) ->
        "Logger.#{method}"

      erlang_logger?(target) and is_atom(method) ->
        ":logger.#{method}"

      MapSet.member?(additional_modules, module_name) and is_atom(method) ->
        "#{module_name}.#{method}"

      true ->
        nil
    end
  end

  defp sink_from_call(_, _), do: nil

  defp logger_alias?({:__aliases__, _, [:Logger]}), do: true
  defp logger_alias?(_), do: false

  defp erlang_logger?(:logger), do: true
  defp erlang_logger?(_), do: false

  defp sink_args({{:., _, _}, _, args}) when is_list(args), do: args
  defp sink_args(_), do: []

  defp collect_evidence(node, %Inventory{} = inventory) do
    {_node, evidence} =
      Macro.prewalk(node, [], fn current_node, acc ->
        fields = fields_for_node(current_node, inventory)

        if fields == [] do
          {current_node, acc}
        else
          type = evidence_type(current_node)
          expression = evidence_expression(current_node, type)
          entry = %Evidence{type: type, expression: expression, fields: fields}
          {current_node, [entry | acc]}
        end
      end)

    Enum.reverse(evidence)
  end

  defp fields_for_node({{:., _, [_receiver, field]}, _, []}, %Inventory{} = inventory)
       when is_atom(field) do
    Inventory.nodes_for_token(inventory, field)
  end

  defp fields_for_node({:%{}, _, pairs}, %Inventory{} = inventory) when is_list(pairs) do
    pairs
    |> Enum.flat_map(fn
      {key, _value} -> Inventory.nodes_for_token(inventory, key)
      _ -> []
    end)
  end

  defp fields_for_node(list, %Inventory{} = inventory) when is_list(list) do
    case keyword_pairs(list) do
      [] ->
        []

      pairs ->
        Enum.flat_map(pairs, fn {key, _value} ->
          Inventory.nodes_for_token(inventory, key)
        end)
    end
  end

  defp fields_for_node({:%, _, [module_ast, _map_ast]}, %Inventory{} = inventory) do
    case Utils.module_name(module_ast) do
      nil ->
        []

      module ->
        if Inventory.prd_module?(inventory, module) do
          inventory.nodes_by_module
          |> Map.get(module, [])
        else
          []
        end
    end
  end

  defp fields_for_node({:inspect, _, [arg]}, %Inventory{} = inventory) do
    case arg do
      {name, _, context} when is_atom(name) and is_atom(context) ->
        if possible_bulk_variable?(name), do: pseudo_fields(inventory), else: []

      _ ->
        []
    end
  end

  defp fields_for_node(_, _), do: []

  defp evidence_type({{:., _, [_receiver, _field]}, _, []}), do: :direct_field_access
  defp evidence_type({:%{}, _, _}), do: :key_match
  defp evidence_type({:%, _, _}), do: :prd_container
  defp evidence_type({:inspect, _, [_]}), do: :bulk_inspect
  defp evidence_type(_), do: :unknown

  defp evidence_expression(node, :direct_field_access), do: Macro.to_string(node)

  defp evidence_expression({:%{}, _, pairs}, :key_match) when is_list(pairs) do
    keys =
      Enum.map(pairs, fn
        {key, _value} -> Utils.normalize_key(key)
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    "map_keys:" <> Enum.join(keys, ",")
  end

  defp evidence_expression(list, :key_match) when is_list(list) do
    keys =
      list
      |> keyword_pairs()
      |> Enum.map(fn {key, _value} -> Utils.normalize_key(key) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    "keyword_keys:" <> Enum.join(keys, ",")
  end

  defp evidence_expression({:%, _, [module_ast, _map_ast]}, :prd_container) do
    module = Utils.module_name(module_ast) || "unknown"
    "prd_container:" <> module
  end

  defp evidence_expression({:inspect, _, [arg]}, :bulk_inspect) do
    variable =
      case arg do
        {name, _, _context} when is_atom(name) -> Atom.to_string(name)
        _ -> "unknown"
      end

    "bulk_inspect:" <> variable
  end

  defp evidence_expression(_node, _type), do: "unknown"

  defp keyword_pairs(list) do
    if Keyword.keyword?(list), do: list, else: []
  end

  defp possible_bulk_variable?(name) when is_atom(name) do
    Atom.to_string(name) in ["params", "payload", "attrs", "attributes", "body", "data"]
  end

  defp pseudo_fields(%Inventory{} = inventory) do
    case inventory.data_nodes do
      [] -> []
      fields -> [hd(fields)]
    end
  end

  defp matched_nodes(evidence) do
    evidence
    |> Enum.flat_map(& &1.fields)
    |> Enum.uniq()
    |> Enum.sort_by(&{&1.module, &1.field || &1.name, &1.class || &1.category, &1.key})
  end

  defp dedupe_evidence(evidence) do
    evidence
    |> Enum.uniq_by(fn entry -> {entry.type, entry.expression, entry.fields} end)
    |> Enum.sort_by(fn entry -> {entry.type, entry.expression, entry.fields} end)
  end

  defp sink_line({_, meta, _}), do: Utils.meta_line(meta)
  defp sink_line(_), do: nil

  defp logging_config(opts) do
    scanners = opts[:scanner_config] || PrivSignal.Config.default_scanners()
    scanners.logging || %PrivSignal.Config.Scanners.Logging{}
  end
end
