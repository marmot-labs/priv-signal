defmodule PrivSignal.Diff.Render.JSON do
  @moduledoc false

  alias PrivSignal.Diff.SemanticV2

  @schema_version "v2"

  def schema_version, do: @schema_version

  def render(report) when is_map(report) do
    events =
      report
      |> Map.get(:events, [])
      |> Enum.map(&normalize_event/1)
      |> Enum.sort_by(&SemanticV2.sort_key/1)

    %{
      version: @schema_version,
      metadata: Map.get(report, :metadata, %{}),
      summary: summary(events),
      events: events
    }
  end

  defp summary(events) do
    counts =
      Enum.reduce(events, %{events_high: 0, events_medium: 0, events_low: 0}, fn event, acc ->
        case Map.get(event, :event_class) do
          "high" -> Map.update!(acc, :events_high, &(&1 + 1))
          "medium" -> Map.update!(acc, :events_medium, &(&1 + 1))
          "low" -> Map.update!(acc, :events_low, &(&1 + 1))
          _ -> acc
        end
      end)

    Map.put(counts, :events_total, length(events))
  end

  defp normalize_event(event) when is_map(event) do
    %{
      event_id: fetch(event, :event_id),
      event_type: fetch(event, :event_type),
      event_class: fetch(event, :event_class),
      rule_id: fetch(event, :rule_id),
      node_id: fetch(event, :node_id),
      edge_id: fetch(event, :edge_id),
      entrypoint_kind: fetch(event, :entrypoint_kind),
      boundary_before: fetch(event, :boundary_before),
      boundary_after: fetch(event, :boundary_after),
      sensitivity_before: fetch(event, :sensitivity_before),
      sensitivity_after: fetch(event, :sensitivity_after),
      destination: fetch(event, :destination, %{}),
      pii_delta: fetch(event, :pii_delta, %{}),
      transform_delta: fetch(event, :transform_delta, %{}),
      details: fetch(event, :details, %{})
    }
  end

  defp fetch(map, key, default \\ nil) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default
  end
end
