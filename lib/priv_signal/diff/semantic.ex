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

    added_ids = MapSet.difference(candidate.flow_ids, base.flow_ids) |> MapSet.to_list()
    removed_ids = MapSet.difference(base.flow_ids, candidate.flow_ids) |> MapSet.to_list()
    shared_ids = MapSet.intersection(base.flow_ids, candidate.flow_ids) |> MapSet.to_list()

    node_changes =
      added_node_keys
      |> Enum.flat_map(fn key ->
        node = Map.fetch!(candidate.data_nodes_by_key, key)
        node_changes(node)
      end)

    added =
      added_ids
      |> Enum.flat_map(fn flow_id ->
        flow = Map.fetch!(candidate.flows_by_id, flow_id)

        [
          change(:flow_added, flow_id, "flow_added", flow_details(flow))
          | semantic_trigger_changes(nil, flow)
        ]
      end)

    removed =
      removed_ids
      |> Enum.map(fn flow_id ->
        flow = Map.fetch!(base.flows_by_id, flow_id)

        change(:flow_removed, flow_id, "flow_removed", flow_details(flow))
      end)

    changed =
      shared_ids
      |> Enum.flat_map(fn flow_id ->
        base_flow = Map.fetch!(base.flows_by_id, flow_id)
        candidate_flow = Map.fetch!(candidate.flows_by_id, flow_id)
        flow_changes(base_flow, candidate_flow, include_confidence?)
      end)

    (node_changes ++ added ++ removed ++ changed)
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
      change(:data_node_added, "node:#{node.key}", "new_inferred_attribute", %{
        key: node.key,
        name: node.name,
        class: node.class,
        sensitive: node.sensitive,
        scope: node.scope
      })
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
      change_type =
        if base_flow.boundary == "internal" and candidate_flow.boundary == "external" do
          "external_sink_added"
        else
          "external_sink_changed"
        end

      change(:flow_changed, base_flow.id, change_type, %{
        before_sink: base_flow.sink,
        after_sink: candidate_flow.sink,
        source_class: candidate_flow.source_class
      })
    end
  end

  defp boundary_change(base_flow, candidate_flow) do
    if base_flow.boundary != candidate_flow.boundary do
      change(:flow_changed, base_flow.id, "boundary_changed", %{
        before_boundary: base_flow.boundary,
        after_boundary: candidate_flow.boundary,
        source_class: candidate_flow.source_class
      })
    end
  end

  defp confidence_change(_base_flow, _candidate_flow, false), do: nil

  defp confidence_change(base_flow, candidate_flow, true) do
    if base_flow.confidence != candidate_flow.confidence do
      change(:confidence_changed, base_flow.id, "confidence_changed", %{
        before_confidence: base_flow.confidence,
        after_confidence: candidate_flow.confidence
      })
    end
  end

  defp semantic_trigger_changes(base_flow, candidate_flow) do
    []
    |> maybe_add_behavioral_signal_persistence(base_flow, candidate_flow)
    |> maybe_add_inferred_attribute_external_transfer(base_flow, candidate_flow)
    |> maybe_add_sensitive_context_linkage(base_flow, candidate_flow)
  end

  defp maybe_add_behavioral_signal_persistence(changes, base_flow, candidate_flow) do
    if behavioral_signal_persistence?(candidate_flow) and
         not behavioral_signal_persistence?(base_flow) do
      [
        change(
          :flow_changed,
          candidate_flow.id,
          "behavioral_signal_persisted",
          flow_details(candidate_flow)
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
          candidate_flow.id,
          "inferred_attribute_external_transfer",
          flow_details(candidate_flow)
        )
        | changes
      ]
    else
      changes
    end
  end

  defp maybe_add_sensitive_context_linkage(changes, base_flow, candidate_flow) do
    if sensitive_context_linkage?(candidate_flow) and not sensitive_context_linkage?(base_flow) do
      [
        change(
          :flow_changed,
          candidate_flow.id,
          "sensitive_context_linkage_added",
          flow_details(candidate_flow)
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

  defp change(type, flow_id, change, details) do
    %{
      type: Atom.to_string(type),
      flow_id: flow_id,
      change: change,
      details: details
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
end
