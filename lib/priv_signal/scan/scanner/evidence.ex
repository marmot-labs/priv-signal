defmodule PrivSignal.Scan.Scanner.Evidence do
  @moduledoc false

  alias PrivSignal.Scan.Evidence
  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Scan.Scanner.Utils

  def collect(node, %Inventory{} = inventory) do
    {_node, evidence} =
      Macro.prewalk(node, [], fn current_node, acc ->
        matches = matches_for_node(current_node, inventory)
        fields = Enum.map(matches, & &1.node)

        if fields == [] do
          {current_node, acc}
        else
          type = evidence_type(current_node)
          expression = evidence_expression(current_node, type)
          match_source = strongest_match_source(matches)

          entry = %Evidence{
            type: type,
            expression: expression,
            fields: fields,
            match_source: match_source
          }

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
    |> Enum.sort_by(&{&1.module, &1.field || &1.name, &1.class, &1.key})
  end

  def dedupe(evidence) do
    evidence
    |> Enum.uniq_by(fn entry ->
      {entry.type, entry.expression, entry.fields, entry.match_source, entry.lineage}
    end)
    |> Enum.sort_by(fn entry ->
      {entry.type, entry.expression, entry.fields, source_rank(entry.match_source), entry.lineage}
    end)
  end

  def matches_for_node({{:., _, [_receiver, field]}, _, []}, %Inventory{} = inventory)
      when is_atom(field) do
    Inventory.matches_for_token(inventory, field)
  end

  def matches_for_node({:%{}, _, pairs}, %Inventory{} = inventory) when is_list(pairs) do
    pairs
    |> Enum.flat_map(fn
      {key, _value} -> Inventory.matches_for_token(inventory, key)
      _ -> []
    end)
  end

  def matches_for_node(list, %Inventory{} = inventory) when is_list(list) do
    case keyword_pairs(list) do
      [] ->
        []

      pairs ->
        Enum.flat_map(pairs, fn {key, _value} ->
          Inventory.matches_for_token(inventory, key)
        end)
    end
  end

  def matches_for_node({:%, _, [module_ast, _map_ast]}, %Inventory{} = inventory) do
    case Utils.module_name(module_ast) do
      nil ->
        []

      module ->
        if Inventory.prd_module?(inventory, module) do
          inventory.nodes_by_module
          |> Map.get(module, [])
          |> Enum.map(&%{node: &1, source: :exact})
        else
          []
        end
    end
  end

  def matches_for_node(value, %Inventory{} = inventory) when is_atom(value) or is_binary(value) do
    Inventory.matches_for_token(inventory, value)
  end

  def matches_for_node(_, _), do: []

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

  defp strongest_match_source(matches) do
    matches
    |> Enum.map(&Map.get(&1, :source))
    |> Enum.min_by(&source_rank/1, fn -> nil end)
  end

  defp source_rank(:exact), do: 0
  defp source_rank(:alias), do: 1
  defp source_rank(:normalized), do: 2
  defp source_rank(_), do: 3
end
