defmodule PrivSignal.Scan.Scanner.Evidence do
  @moduledoc false

  alias PrivSignal.Scan.Evidence
  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Scan.Scanner.Utils

  def collect(node, %Inventory{} = inventory) do
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

    evidence
    |> Enum.reverse()
    |> dedupe()
  end

  def matched_nodes(evidence) do
    evidence
    |> Enum.flat_map(& &1.fields)
    |> Enum.uniq()
    |> Enum.sort_by(&{&1.module, &1.field || &1.name, &1.class || &1.category, &1.key})
  end

  def matched_fields(evidence) do
    matched_nodes(evidence)
  end

  def dedupe(evidence) do
    evidence
    |> Enum.uniq_by(fn entry -> {entry.type, entry.expression, entry.fields} end)
    |> Enum.sort_by(fn entry -> {entry.type, entry.expression, entry.fields} end)
  end

  def fields_for_node({{:., _, [_receiver, field]}, _, []}, %Inventory{} = inventory)
      when is_atom(field) do
    Inventory.fields_for_token(inventory, field)
  end

  def fields_for_node({:%{}, _, pairs}, %Inventory{} = inventory) when is_list(pairs) do
    pairs
    |> Enum.flat_map(fn
      {key, _value} -> Inventory.fields_for_token(inventory, key)
      _ -> []
    end)
  end

  def fields_for_node(list, %Inventory{} = inventory) when is_list(list) do
    case keyword_pairs(list) do
      [] ->
        []

      pairs ->
        Enum.flat_map(pairs, fn {key, _value} ->
          Inventory.fields_for_token(inventory, key)
        end)
    end
  end

  def fields_for_node({:%, _, [module_ast, _map_ast]}, %Inventory{} = inventory) do
    case Utils.module_name(module_ast) do
      nil ->
        []

      module ->
        if Inventory.prd_module?(inventory, module) do
          Map.get(inventory.nodes_by_module, module, [])
        else
          []
        end
    end
  end

  def fields_for_node(value, %Inventory{} = inventory) when is_atom(value) or is_binary(value) do
    Inventory.fields_for_token(inventory, value)
  end

  def fields_for_node(_, _), do: []

  defp evidence_type({{:., _, [_receiver, _field]}, _, []}), do: :direct_field_access
  defp evidence_type({:%{}, _, _}), do: :key_match
  defp evidence_type({:%, _, _}), do: :prd_container
  defp evidence_type(value) when is_atom(value) or is_binary(value), do: :token_match
  defp evidence_type(_), do: :unknown

  defp evidence_expression(node, :direct_field_access), do: Macro.to_string(node)

  defp evidence_expression({:%{}, _, pairs}, :key_match) when is_list(pairs) do
    keys =
      pairs
      |> Enum.map(fn
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

  defp evidence_expression(value, :token_match) when is_atom(value),
    do: "token:" <> Atom.to_string(value)

  defp evidence_expression(value, :token_match) when is_binary(value), do: "token:" <> value

  defp evidence_expression(_node, _type), do: "unknown"

  defp keyword_pairs(list) do
    if Keyword.keyword?(list), do: list, else: []
  end
end
