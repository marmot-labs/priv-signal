defmodule PrivSignal.Diff.Semantic do
  @moduledoc false

  alias PrivSignal.Diff.Normalize

  @persistent_sink_kinds MapSet.new([
                           "database",
                           "database_write",
                           "repo",
                           "s3",
                           "file",
                           "cache"
                         ])

  def compare(base_artifact, candidate_artifact, opts \\ []) do
    include_confidence? = Keyword.get(opts, :include_confidence, false)

    base = Normalize.normalize(base_artifact)
    candidate = Normalize.normalize(candidate_artifact)

    compare_normalized(base, candidate, include_confidence: include_confidence?)
  end

  def compare_normalized(base, candidate, opts \\ []) when is_map(base) and is_map(candidate) do
    include_confidence? = Keyword.get(opts, :include_confidence, false)

    added_node_keys =
      MapSet.difference(candidate.data_node_keys, base.data_node_keys) |> MapSet.to_list()

    shared_ids = MapSet.intersection(base.flow_ids, candidate.flow_ids) |> MapSet.to_list()
    base_only_ids = MapSet.difference(base.flow_ids, candidate.flow_ids) |> MapSet.to_list()
    candidate_only_ids = MapSet.difference(candidate.flow_ids, base.flow_ids) |> MapSet.to_list()

    {stable_pairs, remaining_base_ids, remaining_candidate_ids} =
      pair_by_stable_identity(base_only_ids, candidate_only_ids, base, candidate)

    node_changes =
      added_node_keys
      |> Enum.flat_map(fn key ->
        node = Map.fetch!(candidate.data_nodes_by_key, key)
        node_changes(node)
      end)

    added =
      remaining_candidate_ids
      |> Enum.flat_map(fn flow_id ->
        flow = Map.fetch!(candidate.flows_by_id, flow_id)

        [
          change(:flow_added, flow_id, "flow_added", flow_details(flow), flow.location)
          | semantic_trigger_changes(nil, flow)
        ]
      end)

    removed =
      remaining_base_ids
      |> Enum.map(fn flow_id ->
        flow = Map.fetch!(base.flows_by_id, flow_id)

        change(:flow_removed, flow_id, "flow_removed", flow_details(flow), flow.location)
      end)

    changed_exact =
      shared_ids
      |> Enum.flat_map(fn flow_id ->
        base_flow = Map.fetch!(base.flows_by_id, flow_id)
        candidate_flow = Map.fetch!(candidate.flows_by_id, flow_id)
        flow_changes(base_flow, candidate_flow, include_confidence?)
      end)

    changed_stable =
      stable_pairs
      |> Enum.flat_map(fn {base_id, candidate_id} ->
        base_flow = Map.fetch!(base.flows_by_id, base_id)
        candidate_flow = Map.fetch!(candidate.flows_by_id, candidate_id)
        flow_changes(base_flow, candidate_flow, include_confidence?)
      end)

    (node_changes ++ added ++ removed ++ changed_exact ++ changed_stable)
    |> stable_sort_changes()
  end

  def stable_sort_changes(changes) when is_list(changes) do
    Enum.sort_by(changes, fn change ->
      {
        change.type,
        change.flow_id || "",
        change.change,
        stable_details_key(change.details)
      }
    end)
  end

  defp node_changes(%{class: "inferred_attribute"} = node) do
    [
      change(
        :data_node_added,
        "node:#{node.key}",
        "new_inferred_attribute",
        %{
          key: node.key,
          name: node.name,
          class: node.class,
          sensitive: node.sensitive,
          scope: node.scope
        },
        nil
      )
    ]
  end

  defp node_changes(_node), do: []

  defp flow_changes(base_flow, candidate_flow, include_confidence?) do
    sink_change = sink_change(base_flow, candidate_flow)
    boundary_change = boundary_change(base_flow, candidate_flow)
    confidence_change = confidence_change(base_flow, candidate_flow, include_confidence?)

    semantic_changes = semantic_trigger_changes(base_flow, candidate_flow)

    Enum.reject([sink_change, boundary_change, confidence_change], &is_nil/1) ++ semantic_changes
  end

  defp sink_change(base_flow, candidate_flow) do
    if base_flow.sink != candidate_flow.sink do
      flow_id = flow_change_id(base_flow, candidate_flow)

      change_type =
        if base_flow.boundary == "internal" and candidate_flow.boundary == "external" do
          "external_sink_added"
        else
          "external_sink_changed"
        end

      change(
        :flow_changed,
        flow_id,
        change_type,
        %{
          before_sink: base_flow.sink,
          after_sink: candidate_flow.sink,
          source_class: candidate_flow.source_class
        },
        candidate_flow.location || base_flow.location
      )
    end
  end

  defp boundary_change(base_flow, candidate_flow) do
    if base_flow.boundary != candidate_flow.boundary do
      change(
        :flow_changed,
        flow_change_id(base_flow, candidate_flow),
        "boundary_changed",
        %{
          before_boundary: base_flow.boundary,
          after_boundary: candidate_flow.boundary,
          source_class: candidate_flow.source_class
        },
        candidate_flow.location || base_flow.location
      )
    end
  end

  defp confidence_change(_base_flow, _candidate_flow, false), do: nil

  defp confidence_change(base_flow, candidate_flow, true) do
    if base_flow.confidence != candidate_flow.confidence do
      change(
        :confidence_changed,
        flow_change_id(base_flow, candidate_flow),
        "confidence_changed",
        %{
          before_confidence: base_flow.confidence,
          after_confidence: candidate_flow.confidence
        },
        candidate_flow.location || base_flow.location
      )
    end
  end

  defp semantic_trigger_changes(base_flow, candidate_flow) do
    []
    |> maybe_add_behavioral_signal_persistence(base_flow, candidate_flow)
    |> maybe_add_inferred_attribute_external_transfer(base_flow, candidate_flow)
    |> maybe_add_sensitive_context_linkage(base_flow, candidate_flow)
    |> maybe_add_sensitive_context_unlink(base_flow, candidate_flow)
  end

  defp maybe_add_behavioral_signal_persistence(changes, base_flow, candidate_flow) do
    if behavioral_signal_persistence?(candidate_flow) and
         not behavioral_signal_persistence?(base_flow) do
      [
        change(
          :flow_changed,
          flow_change_id(base_flow, candidate_flow),
          "behavioral_signal_persisted",
          flow_details(candidate_flow),
          candidate_flow.location
        )
        | changes
      ]
    else
      changes
    end
  end

  defp maybe_add_inferred_attribute_external_transfer(changes, base_flow, candidate_flow) do
    if inferred_attribute_external_transfer?(candidate_flow) and
         not inferred_attribute_external_transfer?(base_flow) do
      [
        change(
          :flow_changed,
          flow_change_id(base_flow, candidate_flow),
          "inferred_attribute_external_transfer",
          flow_details(candidate_flow),
          candidate_flow.location
        )
        | changes
      ]
    else
      changes
    end
  end

  defp maybe_add_sensitive_context_linkage(changes, base_flow, candidate_flow) do
    if sensitive_context_linkage?(candidate_flow) and not sensitive_context_linkage?(base_flow) do
      details =
        flow_details(candidate_flow)
        |> Map.put(:added_links, sensitive_context_links(candidate_flow))
        |> Map.put(:removed_links, [])

      [
        change(
          :flow_changed,
          flow_change_id(base_flow, candidate_flow),
          "sensitive_context_linkage_added",
          details,
          candidate_flow.location
        )
        | changes
      ]
    else
      changes
    end
  end

  defp maybe_add_sensitive_context_unlink(changes, base_flow, candidate_flow) do
    if sensitive_context_linkage?(base_flow) and not sensitive_context_linkage?(candidate_flow) do
      details =
        flow_details(candidate_flow || base_flow)
        |> Map.put(:added_links, [])
        |> Map.put(:removed_links, sensitive_context_links(base_flow))

      [
        change(
          :flow_changed,
          flow_change_id(base_flow, candidate_flow),
          "sensitive_context_linkage_removed",
          details,
          base_flow.location || (candidate_flow && candidate_flow.location)
        )
        | changes
      ]
    else
      changes
    end
  end

  defp behavioral_signal_persistence?(nil), do: false

  defp behavioral_signal_persistence?(flow) do
    flow.source_class == "behavioral_signal" and sink_persistence?(flow.sink)
  end

  defp inferred_attribute_external_transfer?(nil), do: false

  defp inferred_attribute_external_transfer?(flow) do
    flow.source_class == "inferred_attribute" and flow.boundary == "external"
  end

  defp sensitive_context_linkage?(nil), do: false

  defp sensitive_context_linkage?(flow) do
    flow.source_class == "persistent_pseudonymous_identifier" and
      Enum.member?(flow.linked_classes || [], "sensitive_context_indicator")
  end

  defp sensitive_context_links(nil), do: []

  defp sensitive_context_links(flow) do
    if flow.source_class == "persistent_pseudonymous_identifier" do
      links =
        (flow.linked_refs || [])
        |> Enum.map(&to_string/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()
        |> Enum.sort()

      if Enum.member?(flow.linked_classes || [], "sensitive_context_indicator"),
        do: links,
        else: []
    else
      []
    end
  end

  defp sink_persistence?(sink) when is_map(sink) do
    kind = Map.get(sink, :kind, "")
    subtype = Map.get(sink, :subtype, "")

    MapSet.member?(@persistent_sink_kinds, kind) or
      String.contains?(String.downcase(subtype), "insert") or
      String.contains?(String.downcase(subtype), "update") or
      String.contains?(String.downcase(subtype), "write") or
      String.contains?(String.downcase(subtype), "put")
  end

  defp sink_persistence?(_), do: false

  defp flow_details(flow) do
    %{
      source: flow.source,
      source_key: flow.source_key,
      source_class: flow.source_class,
      source_sensitive: flow.source_sensitive,
      linked_refs: flow.linked_refs || [],
      linked_classes: flow.linked_classes || [],
      sink: flow.sink,
      boundary: flow.boundary
    }
  end

  defp change(type, flow_id, change, details, location) do
    %{
      type: Atom.to_string(type),
      flow_id: flow_id,
      change: change,
      details: details,
      location: location
    }
  end

  defp stable_details_key(details) when is_map(details) do
    details
    |> Enum.map(fn {key, value} -> {key, stable_value_key(value)} end)
    |> Enum.sort()
  end

  defp stable_details_key(_), do: []

  defp stable_value_key(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> {key, stable_value_key(nested)} end)
    |> Enum.sort()
  end

  defp stable_value_key(value) when is_list(value), do: Enum.map(value, &stable_value_key/1)
  defp stable_value_key(value), do: value

  defp flow_change_id(base_flow, candidate_flow) do
    candidate_id = candidate_flow && candidate_flow.stable_id
    base_id = base_flow && base_flow.stable_id

    cond do
      is_binary(candidate_id) and candidate_id != "" -> candidate_id
      is_binary(base_id) and base_id != "" -> base_id
      is_binary(candidate_flow && candidate_flow.id) -> candidate_flow.id
      true -> base_flow && base_flow.id
    end
  end

  defp pair_by_stable_identity(base_ids, candidate_ids, base, candidate) do
    base_by_stable =
      Enum.group_by(base_ids, fn id -> Map.fetch!(base.flows_by_id, id).stable_id end)

    candidate_by_stable =
      Enum.group_by(candidate_ids, fn id -> Map.fetch!(candidate.flows_by_id, id).stable_id end)

    stable_keys =
      Map.keys(base_by_stable)
      |> MapSet.new()
      |> MapSet.intersection(MapSet.new(Map.keys(candidate_by_stable)))
      |> MapSet.to_list()
      |> Enum.sort()

    {pairs, matched_base, matched_candidate} =
      Enum.reduce(stable_keys, {[], MapSet.new(), MapSet.new()}, fn stable_id,
                                                                    {pairs_acc, base_acc,
                                                                     candidate_acc} ->
        base_list = Map.get(base_by_stable, stable_id, []) |> Enum.sort()
        candidate_list = Map.get(candidate_by_stable, stable_id, []) |> Enum.sort()

        if length(base_list) == 1 and length(candidate_list) == 1 do
          [base_id] = base_list
          [candidate_id] = candidate_list

          {pairs_acc ++ [{base_id, candidate_id}], MapSet.put(base_acc, base_id),
           MapSet.put(candidate_acc, candidate_id)}
        else
          {pairs_acc, base_acc, candidate_acc}
        end
      end)

    remaining_base_ids = Enum.reject(base_ids, &MapSet.member?(matched_base, &1))
    remaining_candidate_ids = Enum.reject(candidate_ids, &MapSet.member?(matched_candidate, &1))

    {pairs, remaining_base_ids, remaining_candidate_ids}
  end
end
