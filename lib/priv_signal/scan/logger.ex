defmodule PrivSignal.Scan.Logger do
  @moduledoc false

  alias PrivSignal.Scan.Evidence
  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Validate.AST

  def scan_file(path, %Inventory{} = inventory) do
    with {:ok, ast} <- AST.parse_file(path) do
      {:ok, scan_ast(ast, path, inventory)}
    end
  end

  def scan_ast(ast, path, %Inventory{} = inventory) do
    ast
    |> AST.extract_modules()
    |> Enum.flat_map(fn module_info ->
      forms = AST.module_forms(module_info.body)
      function_defs = extract_function_defs(forms)

      Enum.flat_map(function_defs, fn function_def ->
        scan_function(path, module_info.name, function_def, inventory)
      end)
    end)
    |> Enum.sort_by(&{&1.file, &1.line, &1.module, &1.function, &1.arity, &1.sink})
  end

  defp scan_function(path, module_name, function_def, inventory) do
    {_node, findings} =
      Macro.prewalk(function_def.body, [], fn node, acc ->
        case sink_from_call(node) do
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
      matched_fields = matched_fields(evidence)

      finding = %{
        module: module_name,
        function: function_def.name,
        arity: function_def.arity,
        file: path,
        line: line,
        sink: sink,
        matched_fields: matched_fields,
        evidence: evidence
      }

      [finding | acc]
    end
  end

  defp extract_function_defs(forms) do
    Enum.flat_map(forms, fn form ->
      case form do
        {kind, meta, args} when kind in [:def, :defp] ->
          case extract_def(args) do
            {:ok, name, arity, body} ->
              [%{name: Atom.to_string(name), arity: arity, body: body, line: meta_line(meta)}]

            :error ->
              []
          end

        _ ->
          []
      end
    end)
  end

  defp extract_def([head, body_kw]) when is_list(body_kw) do
    with {:ok, name, args_ast} <- extract_head_name_and_args(head) do
      body = Keyword.get(body_kw, :do)
      arity = length(args_ast || [])
      {:ok, name, arity, body}
    end
  end

  defp extract_def(_), do: :error

  defp extract_head_name_and_args({:when, _meta, [head | _guards]}) do
    extract_head_name_and_args(head)
  end

  defp extract_head_name_and_args({name, _meta, args_ast}) when is_atom(name) do
    {:ok, name, args_ast || []}
  end

  defp extract_head_name_and_args(_), do: :error

  defp sink_from_call({{:., _, [target, method]}, _, _args}) do
    cond do
      logger_alias?(target) and is_atom(method) -> "Logger.#{method}"
      erlang_logger?(target) and is_atom(method) -> ":logger.#{method}"
      true -> nil
    end
  end

  defp sink_from_call(_), do: nil

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
    Inventory.fields_for_token(inventory, field)
  end

  defp fields_for_node({:%{}, _, pairs}, %Inventory{} = inventory) when is_list(pairs) do
    pairs
    |> Enum.flat_map(fn
      {key, _value} -> Inventory.fields_for_token(inventory, key)
      _ -> []
    end)
  end

  defp fields_for_node(list, %Inventory{} = inventory) when is_list(list) do
    case keyword_pairs(list) do
      [] ->
        []

      pairs ->
        Enum.flat_map(pairs, fn {key, _value} ->
          Inventory.fields_for_token(inventory, key)
        end)
    end
  end

  defp fields_for_node({:%, _, [module_ast, _map_ast]}, %Inventory{} = inventory) do
    case module_name(module_ast) do
      nil ->
        []

      module ->
        if Inventory.pii_module?(inventory, module) do
          inventory.fields_by_module
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
  defp evidence_type({:%, _, _}), do: :pii_container
  defp evidence_type({:inspect, _, [_]}), do: :bulk_inspect
  defp evidence_type(_), do: :unknown

  defp evidence_expression(node, :direct_field_access), do: Macro.to_string(node)

  defp evidence_expression({:%{}, _, pairs}, :key_match) when is_list(pairs) do
    keys =
      Enum.map(pairs, fn
        {key, _value} -> normalize_key(key)
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
      |> Enum.map(fn {key, _value} -> normalize_key(key) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    "keyword_keys:" <> Enum.join(keys, ",")
  end

  defp evidence_expression({:%, _, [module_ast, _map_ast]}, :pii_container) do
    module = module_name(module_ast) || "unknown"
    "pii_container:" <> module
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
    case inventory.fields do
      [] -> []
      fields -> [hd(fields)]
    end
  end

  defp matched_fields(evidence) do
    evidence
    |> Enum.flat_map(& &1.fields)
    |> Enum.uniq()
    |> Enum.sort_by(&{&1.module, &1.name, &1.category, &1.sensitivity})
  end

  defp dedupe_evidence(evidence) do
    evidence
    |> Enum.uniq_by(fn entry -> {entry.type, entry.expression, entry.fields} end)
    |> Enum.sort_by(fn entry -> {entry.type, entry.expression, entry.fields} end)
  end

  defp sink_line({_, meta, _}), do: meta_line(meta)
  defp sink_line(_), do: nil

  defp meta_line(meta) when is_list(meta), do: Keyword.get(meta, :line)
  defp meta_line(_), do: nil

  defp module_name({:__aliases__, _, parts}) when is_list(parts) do
    parts
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(".")
  end

  defp module_name(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> case do
      "Elixir." <> rest -> rest
      other -> other
    end
  end

  defp module_name(_), do: nil

  defp normalize_key(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_key(value) when is_binary(value), do: value
  defp normalize_key(_), do: nil
end
