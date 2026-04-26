defmodule PrivSignal.Scan.Inventory do
  @moduledoc """
  Builds the searchable PRD-node inventory used by scan rules.
  """

  alias PrivSignal.Config
  alias PrivSignal.Config.PRD

  defstruct modules: MapSet.new(),
            data_nodes: [],
            nodes_by_key: %{},
            nodes_by_module: %{},
            key_tokens: MapSet.new(),
            token_nodes: %{},
            normalized_token_nodes: %{},
            alias_token_nodes: %{},
            alias_canonical_tokens: MapSet.new(),
            matching: %PrivSignal.Config.Matching{},
            strict_exact_only: false

  def build(%Config{} = config) do
    data_nodes =
      config
      |> PRD.entries()
      |> Enum.map(fn node ->
        module_name = normalize_module(node.scope && node.scope.module)
        field_name = normalize_token(node.scope && node.scope.field)

        %{
          key: normalize_token(node.key),
          label: normalize_label(node.label),
          class: normalize_class(node.class),
          sensitive: node.sensitive == true,
          module: module_name,
          field: field_name,
          name: field_name,
          reference: reference(module_name, field_name)
        }
      end)
      |> Enum.reject(&(is_nil(&1.key) or is_nil(&1.module) or is_nil(&1.field)))
      |> Enum.uniq()
      |> Enum.sort_by(&{&1.key, &1.module, &1.field, &1.class, &1.sensitive})

    modules =
      data_nodes
      |> Enum.map(& &1.module)
      |> MapSet.new()

    nodes_by_key = Map.new(data_nodes, &{&1.key, &1})

    nodes_by_module =
      data_nodes
      |> Enum.group_by(& &1.module)
      |> Map.new(fn {module, entries} ->
        {module, Enum.sort_by(entries, &{&1.field, &1.class, &1.key})}
      end)

    token_nodes =
      data_nodes
      |> Enum.group_by(& &1.field)
      |> Map.new(fn {token, entries} ->
        {token, Enum.sort_by(entries, &{&1.module, &1.class, &1.key})}
      end)

    matching = config.matching || Config.default_matching()
    normalized_token_nodes = build_normalized_index(data_nodes, matching)
    alias_token_nodes = build_alias_index(token_nodes, matching)
    alias_canonical_tokens = alias_canonical_tokens(matching)

    %__MODULE__{
      modules: modules,
      data_nodes: data_nodes,
      nodes_by_key: nodes_by_key,
      nodes_by_module: nodes_by_module,
      key_tokens: MapSet.new(Map.keys(token_nodes)),
      token_nodes: token_nodes,
      normalized_token_nodes: normalized_token_nodes,
      alias_token_nodes: alias_token_nodes,
      alias_canonical_tokens: alias_canonical_tokens,
      matching: matching,
      strict_exact_only: config.strict_exact_only == true
    }
  end

  def nodes_for_token(%__MODULE__{} = inventory, token) do
    matches_for_token(inventory, token)
    |> Enum.map(& &1.node)
  end

  def matches_for_token(%__MODULE__{} = inventory, token) do
    normalized = normalize_token(token)

    if is_nil(normalized) do
      []
    else
      exact = Map.get(inventory.token_nodes, normalized, [])

      if inventory.strict_exact_only do
        []
        |> append_matches(exact, :exact)
        |> dedupe_matches()
      else
        alias_matches = Map.get(inventory.alias_token_nodes, normalized, [])

        normalized_matches =
          token
          |> lookup_normalized_candidates(inventory)
          |> Enum.flat_map(&Map.get(inventory.normalized_token_nodes, &1, []))

        []
        |> append_matches(exact, :exact)
        |> append_matches(alias_matches, :alias)
        |> append_matches(normalized_matches, :normalized)
        |> dedupe_matches()
      end
    end
  end

  def prd_module?(%__MODULE__{} = inventory, module_name) do
    MapSet.member?(inventory.modules, normalize_module(module_name))
  end

  def key_token?(%__MODULE__{} = inventory, token) do
    normalize_token(token) in Map.keys(inventory.token_nodes)
  end

  defp append_matches(acc, nodes, source) do
    Enum.reduce(nodes, acc, fn node, list -> [%{node: node, source: source} | list] end)
  end

  defp dedupe_matches(matches) do
    matches
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn %{node: node, source: source}, acc ->
      key = {node.module, node.field || node.name, node.key}
      previous = Map.get(acc, key)

      case previous do
        nil ->
          Map.put(acc, key, %{node: node, source: source})

        %{source: existing_source} ->
          if source_rank(source) < source_rank(existing_source) do
            Map.put(acc, key, %{node: node, source: source})
          else
            acc
          end
      end
    end)
    |> Map.values()
    |> Enum.sort_by(fn %{node: node, source: source} ->
      {node.module, node.field || node.name, node.class, node.key, source_rank(source)}
    end)
  end

  defp source_rank(:exact), do: 0
  defp source_rank(:alias), do: 1
  defp source_rank(:normalized), do: 2
  defp source_rank(_), do: 3

  defp normalize_token(nil), do: nil

  defp normalize_token(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_token()
  end

  defp normalize_token(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      token -> token
    end
  end

  defp normalize_token(_), do: nil

  defp build_normalized_index(data_nodes, matching) do
    Enum.reduce(data_nodes, %{}, fn node, acc ->
      candidates = normalized_index_candidates(node.field, matching)

      Enum.reduce(candidates, acc, fn token, token_acc ->
        Map.update(token_acc, token, [node], fn nodes ->
          [node | nodes]
        end)
      end)
    end)
    |> Map.new(fn {token, nodes} ->
      {token, nodes |> Enum.uniq() |> Enum.sort_by(&{&1.module, &1.field, &1.class, &1.key})}
    end)
  end

  defp alias_canonical_tokens(matching) do
    matching
    |> Map.get(:aliases, %{})
    |> Map.values()
    |> Enum.map(&normalize_token/1)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp build_alias_index(token_nodes, matching) do
    aliases = matching.aliases || %{}

    Enum.reduce(aliases, %{}, fn {alias_token, canonical}, acc ->
      alias_key = normalize_token(alias_token)
      canonical_key = normalize_token(canonical)
      nodes = Map.get(token_nodes, canonical_key, [])

      if is_nil(alias_key) or is_nil(canonical_key) or nodes == [] do
        acc
      else
        Map.put(acc, alias_key, nodes)
      end
    end)
  end

  defp normalized_index_candidates(token, matching) do
    {base, parts, prefix_candidates} = normalized_candidate_parts(token, matching)

    if is_nil(base) do
      []
    else
      ([base] ++ conservative_suffix_candidates(parts) ++ prefix_candidates)
      |> Enum.map(&normalize_token/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
    end
  end

  defp lookup_normalized_candidates(token, inventory) do
    {base, parts, prefix_candidates} = normalized_candidate_parts(token, inventory.matching)

    if is_nil(base) do
      []
    else
      single_part_candidates =
        parts
        |> Enum.filter(&(length(parts) == 2 and meaningful_single_part?(&1)))
        |> Enum.filter(fn part ->
          MapSet.member?(inventory.key_tokens, part) or
            MapSet.member?(inventory.alias_canonical_tokens, part)
        end)

      ([base] ++
         conservative_suffix_candidates(parts) ++ prefix_candidates ++ single_part_candidates)
      |> Enum.map(&normalize_token/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
    end
  end

  defp normalized_candidate_parts(token, matching) do
    token = normalize_raw_token(token)

    if is_nil(token) do
      {nil, [], []}
    else
      split_case = Map.get(matching, :split_case, true)
      singularize = Map.get(matching, :singularize, true)
      strip_prefixes = Map.get(matching, :strip_prefixes, [])

      base =
        token
        |> maybe_split_case(split_case)
        |> String.replace(~r/[^a-z0-9]+/u, "_")
        |> String.trim("_")

      parts =
        base
        |> String.split("_", trim: true)
        |> Enum.reject(&(&1 == ""))
        |> maybe_singularize(singularize)

      prefix_candidates =
        strip_prefixes
        |> Enum.map(&normalize_token/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.flat_map(fn prefix ->
          if String.starts_with?(base, prefix <> "_") do
            base
            |> String.replace_prefix(prefix <> "_", "")
            |> normalize_candidate(singularize)
          else
            []
          end
        end)

      {base, parts, prefix_candidates}
    end
  end

  defp conservative_suffix_candidates(parts) when length(parts) < 2, do: []

  defp conservative_suffix_candidates(parts) do
    2..length(parts)
    |> Enum.flat_map(fn suffix_length ->
      suffix = Enum.take(parts, -suffix_length)

      if valid_suffix_candidate?(suffix) do
        [Enum.join(suffix, "_")]
      else
        []
      end
    end)
  end

  defp valid_suffix_candidate?(suffix_parts) when length(suffix_parts) < 2, do: false

  defp valid_suffix_candidate?(suffix_parts) do
    head = List.first(suffix_parts)
    tail = List.last(suffix_parts)

    not generic_segment?(head) and not generic_segment?(tail)
  end

  defp normalize_candidate(candidate, singularize) do
    candidate
    |> String.split("_", trim: true)
    |> maybe_singularize(singularize)
    |> case do
      [] -> []
      normalized_parts -> [Enum.join(normalized_parts, "_")]
    end
  end

  defp meaningful_single_part?(part), do: part in ["email", "phone", "ssn"]

  defp generic_segment?(segment), do: segment in ["id", "user", "client", "context", "request"]

  defp normalize_raw_token(nil), do: nil

  defp normalize_raw_token(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_raw_token()
  end

  defp normalize_raw_token(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      token -> token
    end
  end

  defp normalize_raw_token(_), do: nil

  defp maybe_split_case(value, true) when is_binary(value) do
    value
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.downcase()
  end

  defp maybe_split_case(value, _), do: value

  defp maybe_singularize(parts, true) do
    Enum.map(parts, &singularize_part/1)
  end

  defp maybe_singularize(parts, _), do: parts

  defp singularize_part(part) do
    cond do
      String.ends_with?(part, "ies") and String.length(part) > 3 ->
        String.slice(part, 0, String.length(part) - 3) <> "y"

      String.ends_with?(part, "s") and not String.ends_with?(part, "ss") and
          String.length(part) > 1 ->
        String.slice(part, 0, String.length(part) - 1)

      true ->
        part
    end
  end

  defp normalize_label(nil), do: nil

  defp normalize_label(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_label(value), do: value |> to_string() |> normalize_label()

  defp normalize_class(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> "direct_identifier"
      normalized -> normalized
    end
  end

  defp normalize_class(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_class()

  defp normalize_class(_), do: "direct_identifier"

  defp reference(nil, field), do: field
  defp reference(module, nil), do: module
  defp reference(module, field), do: module <> "." <> field

  defp normalize_module("Elixir." <> rest), do: rest

  defp normalize_module(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_module(_), do: nil
end
