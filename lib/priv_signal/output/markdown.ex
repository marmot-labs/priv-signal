defmodule PrivSignal.Output.Markdown do
  @moduledoc false

  def render(%{category: category, reasons: reasons, events: events}) do
    lines = ["## PrivSignal Privacy Risk", "", "**Category:** #{format_category(category)}", ""]

    lines =
      if reasons == [] do
        lines ++ ["No privacy-relevant changes detected."]
      else
        lines ++ ["**Contributing factors:**", "" | Enum.map(reasons, &"- #{&1}")]
      end

    lines =
      if events == [] do
        lines
      else
        lines ++ ["", "**Evidence:**", "" | Enum.map(events, &format_event/1)]
      end

    Enum.join(lines, "\n")
  end

  defp format_category(category) do
    category
    |> Atom.to_string()
    |> String.upcase()
  end

  defp format_event(event) do
    summary = event.summary

    summary_text =
      if is_binary(summary) and String.trim(summary) != "" do
        " — #{summary}"
      else
        ""
      end

    "- #{format_event_type(event.type)}: #{event_label(event)}#{summary_text} (#{event.evidence})"
  end

  defp format_event_type(:flow_touched), do: "Flow touched"
  defp format_event_type(:new_pii), do: "New PII"
  defp format_event_type(:new_sink), do: "New sink"
  defp format_event_type(other), do: to_string(other)

  defp event_label(%{type: :flow_touched, flow_id: flow_id})
       when is_binary(flow_id) and flow_id != "" do
    flow_id
  end

  defp event_label(%{type: :new_pii, pii_category: pii_category})
       when is_binary(pii_category) and pii_category != "" do
    pii_category
  end

  defp event_label(%{type: :new_sink, sink: sink}) when is_binary(sink) and sink != "" do
    sink
  end

  defp event_label(_event), do: "unknown"
end
