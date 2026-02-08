defmodule PrivSignal.Diff.Render.Human do
  @moduledoc false

  def render(report) when is_map(report) do
    changes = Map.get(report, :changes, [])

    if changes == [] do
      "Privacy-Relevant Changes Detected\n\nNo semantic privacy changes found."
    else
      grouped =
        changes
        |> Enum.group_by(&Map.get(&1, :severity))

      sections =
        [
          section("HIGH", Map.get(grouped, "high", [])),
          section("MEDIUM", Map.get(grouped, "medium", [])),
          section("LOW", Map.get(grouped, "low", []))
        ]
        |> Enum.reject(&(&1 == ""))

      (["Privacy-Relevant Changes Detected", ""] ++ sections)
      |> Enum.join("\n")
    end
  end

  defp section(_title, []), do: ""

  defp section(title, changes) do
    lines =
      changes
      |> stable_sort()
      |> Enum.map(&render_change/1)

    ([title <> ":" | lines] ++ [""])
    |> Enum.join("\n")
  end

  defp stable_sort(changes) do
    Enum.sort_by(changes, fn change ->
      {Map.get(change, :flow_id) || "", Map.get(change, :type) || "",
       Map.get(change, :change) || ""}
    end)
  end

  defp render_change(%{type: "flow_added"} = change) do
    details = Map.get(change, :details, %{})
    sink = format_sink(Map.get(details, :sink))
    boundary = Map.get(details, :boundary, "unknown")
    "- Flow added: #{change.flow_id} (sink: #{sink}, boundary: #{boundary}) [#{change.rule_id}]"
  end

  defp render_change(%{type: "flow_removed"} = change) do
    "- Flow removed: #{change.flow_id} [#{change.rule_id}]"
  end

  defp render_change(%{type: "confidence_changed"} = change) do
    details = Map.get(change, :details, %{})
    before_confidence = Map.get(details, :before_confidence, "n/a")
    after_confidence = Map.get(details, :after_confidence, "n/a")

    "- Confidence changed: #{change.flow_id} (#{before_confidence} -> #{after_confidence}) [#{change.rule_id}]"
  end

  defp render_change(%{type: "flow_changed", change: "boundary_changed"} = change) do
    details = Map.get(change, :details, %{})

    "- Boundary changed: #{change.flow_id} (#{Map.get(details, :before_boundary, "unknown")} -> #{Map.get(details, :after_boundary, "unknown")}) [#{change.rule_id}]"
  end

  defp render_change(%{type: "flow_changed", change: "external_sink_added"} = change) do
    details = Map.get(change, :details, %{})
    after_sink = format_sink(Map.get(details, :after_sink))
    "- External sink added: #{change.flow_id} (sink: #{after_sink}) [#{change.rule_id}]"
  end

  defp render_change(%{type: "flow_changed", change: "external_sink_added_removed"} = change) do
    details = Map.get(change, :details, %{})
    before_sink = format_sink(Map.get(details, :before_sink))
    after_sink = format_sink(Map.get(details, :after_sink))
    "- Sink changed: #{change.flow_id} (#{before_sink} -> #{after_sink}) [#{change.rule_id}]"
  end

  defp render_change(%{type: "flow_changed", change: "pii_fields_expanded"} = change) do
    details = Map.get(change, :details, %{})
    fields = Map.get(details, :added_fields, []) |> Enum.join(", ")
    "- PII fields expanded: #{change.flow_id} (added: #{fields}) [#{change.rule_id}]"
  end

  defp render_change(%{type: "flow_changed", change: "pii_fields_reduced"} = change) do
    details = Map.get(change, :details, %{})
    fields = Map.get(details, :removed_fields, []) |> Enum.join(", ")
    "- PII fields reduced: #{change.flow_id} (removed: #{fields}) [#{change.rule_id}]"
  end

  defp render_change(change) do
    "- #{Map.get(change, :type)}: #{Map.get(change, :flow_id)} (#{Map.get(change, :change)}) [#{Map.get(change, :rule_id, "R-LOW-DEFAULT")}]"
  end

  defp format_sink(nil), do: "unknown"

  defp format_sink(sink) when is_map(sink) do
    kind = Map.get(sink, :kind) || Map.get(sink, "kind") || "unknown"
    subtype = Map.get(sink, :subtype) || Map.get(sink, "subtype") || "unknown"
    "#{kind}:#{subtype}"
  end
end
