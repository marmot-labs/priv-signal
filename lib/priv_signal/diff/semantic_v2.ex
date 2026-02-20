defmodule PrivSignal.Diff.SemanticV2 do
  @moduledoc false

  alias PrivSignal.Diff.EventId

  @high_fields MapSet.new(["ssn", "dob", "date_of_birth", "passport_number"])

  def from_changes(changes) when is_list(changes) do
    changes
    |> Enum.map(&to_event/1)
    |> Enum.sort_by(&sort_key/1)
  end

  def sort_key(event) when is_map(event) do
    {
      class_rank(fetch(event, :event_class)),
      fetch(event, :event_type, ""),
      fetch(event, :event_id, ""),
      fetch(event, :node_id, ""),
      fetch(event, :edge_id, ""),
      stable_map_key(fetch(event, :details, %{}))
    }
  end

  defp to_event(change) do
    event_type = map_event_type(change)
    details = Map.get(change, :details, %{})
    boundary_before = boundary_before(change, details)
    boundary_after = boundary_after(change, details)

    event = %{
      event_type: event_type,
      event_class: Map.get(change, :severity, "low"),
      rule_id: Map.get(change, :rule_id),
      node_id: nil,
      edge_id: Map.get(change, :flow_id),
      entrypoint_kind: entrypoint_kind(details),
      boundary_before: boundary_before,
      boundary_after: boundary_after,
      sensitivity_before: sensitivity_before(change, details),
      sensitivity_after: sensitivity_after(change, details),
      destination: destination(change, details),
      pii_delta: pii_delta(change, details),
      transform_delta: %{"added" => [], "removed" => []},
      details: details
    }

    Map.put(event, :event_id, EventId.generate(event))
  end

  defp map_event_type(%{type: "flow_added"}), do: "edge_added"
  defp map_event_type(%{type: "flow_removed"}), do: "edge_removed"
  defp map_event_type(%{type: "data_node_added"}), do: "node_added"
  defp map_event_type(%{type: "confidence_changed"}), do: "edge_updated"
  defp map_event_type(%{type: "flow_changed", change: "boundary_changed"}), do: "boundary_changed"

  defp map_event_type(%{type: "flow_changed", change: "external_sink_added"}),
    do: "destination_changed"

  defp map_event_type(%{type: "flow_changed", change: "external_sink_changed"}),
    do: "destination_changed"

  defp map_event_type(%{type: "flow_changed", change: "inferred_attribute_external_transfer"}),
    do: "destination_changed"

  defp map_event_type(%{type: "flow_changed", change: "sensitive_context_linkage_added"}),
    do: "transform_changed"

  defp map_event_type(%{type: "flow_changed", change: "behavioral_signal_persisted"}),
    do: "sensitivity_changed"

  defp map_event_type(%{type: "flow_changed", change: "pii_fields_expanded"}),
    do: "sensitivity_changed"

  defp map_event_type(%{type: "flow_changed", change: "pii_fields_reduced"}),
    do: "sensitivity_changed"

  defp map_event_type(_), do: "edge_updated"

  defp entrypoint_kind(details) do
    source = fetch(details, :source, "")

    cond do
      String.contains?(source, "Controller") -> "controller"
      String.contains?(source, "Live") -> "liveview"
      true -> "unknown"
    end
  end

  defp boundary_before(%{type: "flow_changed", change: "boundary_changed"}, details),
    do: fetch(details, :before_boundary, "internal")

  defp boundary_before(_change, _details), do: "internal"

  defp boundary_after(%{type: "flow_added"}, details), do: fetch(details, :boundary, "internal")
  defp boundary_after(%{type: "flow_removed"}, details), do: fetch(details, :boundary, "internal")

  defp boundary_after(%{type: "flow_changed", change: "boundary_changed"}, details),
    do: fetch(details, :after_boundary, "internal")

  defp boundary_after(_change, _details), do: "internal"

  defp sensitivity_before(%{change: "pii_fields_reduced"}, _details), do: "medium"
  defp sensitivity_before(%{change: "pii_fields_expanded"}, _details), do: "low"
  defp sensitivity_before(%{change: "behavioral_signal_persisted"}, _details), do: "low"
  defp sensitivity_before(_, _), do: "low"

  defp sensitivity_after(%{change: "pii_fields_expanded"} = change, details) do
    fields =
      fetch(details, :added_fields, [])
      |> Enum.map(&normalize_field/1)
      |> MapSet.new()

    if MapSet.size(MapSet.intersection(fields, @high_fields)) > 0 or
         Map.get(change, :severity) == "high" do
      "high"
    else
      "medium"
    end
  end

  defp sensitivity_after(%{change: "pii_fields_reduced"}, _details), do: "low"
  defp sensitivity_after(%{change: "behavioral_signal_persisted"}, _details), do: "medium"
  defp sensitivity_after(%{change: "sensitive_context_linkage_added"}, _details), do: "high"
  defp sensitivity_after(%{severity: "high"}, _details), do: "high"
  defp sensitivity_after(%{severity: "medium"}, _details), do: "medium"
  defp sensitivity_after(_change, _details), do: "low"

  defp destination(%{change: "external_sink_added"} = _change, details),
    do: sink_to_destination(fetch(details, :after_sink, %{}))

  defp destination(%{change: "external_sink_changed"} = _change, details),
    do: sink_to_destination(fetch(details, :after_sink, %{}))

  defp destination(%{change: "inferred_attribute_external_transfer"} = _change, details),
    do: sink_to_destination(fetch(details, :sink, %{}))

  defp destination(%{type: "flow_added"}, details),
    do: sink_to_destination(fetch(details, :sink, %{}))

  defp destination(_, _), do: %{"kind" => "unknown", "vendor" => "unknown", "domain" => nil}

  defp sink_to_destination(sink) when is_map(sink) do
    kind = fetch(sink, :kind, "unknown")
    subtype = fetch(sink, :subtype, "unknown")

    %{
      "kind" => kind,
      "vendor" => vendor_from_sink(kind, subtype),
      "domain" => nil
    }
  end

  defp sink_to_destination(_), do: %{"kind" => "unknown", "vendor" => "unknown", "domain" => nil}

  defp vendor_from_sink("http", subtype), do: subtype
  defp vendor_from_sink(kind, _subtype) when is_binary(kind), do: kind
  defp vendor_from_sink(_, _), do: "unknown"

  defp pii_delta(%{change: "pii_fields_expanded"}, details) do
    fields = fetch(details, :added_fields, [])
    %{"added_categories" => [], "added_fields" => fields}
  end

  defp pii_delta(%{change: "pii_fields_reduced"}, details) do
    fields = fetch(details, :removed_fields, [])
    %{"added_categories" => [], "added_fields" => [], "removed_fields" => fields}
  end

  defp pii_delta(%{change: "new_inferred_attribute"}, details) do
    class = fetch(details, :class, "inferred_attribute")
    %{"added_categories" => [class], "added_fields" => [fetch(details, :key)]}
  end

  defp pii_delta(%{change: "behavioral_signal_persisted"}, details) do
    %{
      "added_categories" => [fetch(details, :source_class, "behavioral_signal")],
      "added_fields" => [fetch(details, :source_key)]
    }
  end

  defp pii_delta(%{change: "inferred_attribute_external_transfer"}, details) do
    %{
      "added_categories" => [fetch(details, :source_class, "inferred_attribute")],
      "added_fields" => [fetch(details, :source_key)]
    }
  end

  defp pii_delta(%{change: "sensitive_context_linkage_added"}, details) do
    %{
      "added_categories" => fetch(details, :linked_classes, []),
      "added_fields" => fetch(details, :linked_refs, [])
    }
  end

  defp pii_delta(_, _), do: %{"added_categories" => [], "added_fields" => []}

  defp class_rank("high"), do: 0
  defp class_rank("medium"), do: 1
  defp class_rank("low"), do: 2
  defp class_rank(_), do: 3

  defp stable_map_key(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), stable_value_key(value)} end)
    |> Enum.sort()
  end

  defp stable_map_key(_), do: []

  defp stable_value_key(value) when is_map(value), do: stable_map_key(value)
  defp stable_value_key(value) when is_list(value), do: Enum.map(value, &stable_value_key/1)
  defp stable_value_key(value), do: value

  defp normalize_field(value) when is_binary(value),
    do: value |> String.trim() |> String.downcase()

  defp normalize_field(value), do: to_string(value) |> normalize_field()

  defp fetch(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default
  end
end
