defmodule PrivSignal.Diff.Severity do
  @moduledoc false

  @default_rule_id "R-LOW-DEFAULT"

  def annotate(changes) when is_list(changes) do
    changes
    |> Enum.map(&annotate_change/1)
    |> Enum.sort_by(&sort_key/1)
  end

  defp annotate_change(change) when is_map(change) do
    {severity, rule_id} = classify(change)
    change |> Map.put(:severity, severity) |> Map.put(:rule_id, rule_id)
  end

  defp classify(%{type: "flow_added", details: details}) do
    if details_value(details, :boundary) == "external" do
      {"high", "R-HIGH-EXTERNAL-FLOW-ADDED"}
    else
      {"medium", "R-MEDIUM-INTERNAL-FLOW-ADDED"}
    end
  end

  defp classify(%{type: "flow_removed"}) do
    {"low", "R-LOW-FLOW-REMOVED"}
  end

  defp classify(%{type: "data_node_added", change: "new_inferred_attribute"}) do
    {"medium", "R-MEDIUM-NEW-INFERRED-ATTRIBUTE"}
  end

  defp classify(%{type: "confidence_changed"}) do
    {"low", "R-LOW-CONFIDENCE-ONLY"}
  end

  defp classify(%{type: "flow_changed", change: "external_sink_added"}) do
    {"high", "R-HIGH-EXTERNAL-SINK-ADDED"}
  end

  defp classify(%{type: "flow_changed", change: "external_sink_changed"}) do
    {"high", "R-HIGH-EXTERNAL-SINK-CHANGED"}
  end

  defp classify(%{type: "flow_changed", change: "boundary_changed", details: details}) do
    if details_value(details, :after_boundary) == "external" do
      {"high", "R-HIGH-BOUNDARY-EXITS-SYSTEM"}
    else
      {"low", "R-LOW-BOUNDARY-INTERNALIZED"}
    end
  end

  defp classify(%{type: "flow_changed", change: "behavioral_signal_persisted"}) do
    {"medium", "R-MEDIUM-BEHAVIORAL-SIGNAL-PERSISTED"}
  end

  defp classify(%{type: "flow_changed", change: "inferred_attribute_external_transfer"}) do
    {"high", "R-HIGH-INFERRED-ATTRIBUTE-EXTERNAL-TRANSFER"}
  end

  defp classify(%{type: "flow_changed", change: "sensitive_context_linkage_added"}) do
    {"high", "R-HIGH-SENSITIVE-CONTEXT-LINKAGE"}
  end

  defp classify(_change) do
    {"low", @default_rule_id}
  end

  defp sort_key(change) do
    {severity_rank(Map.get(change, :severity) || Map.get(change, "severity")),
     Map.get(change, :flow_id) || "", Map.get(change, :type) || "",
     Map.get(change, :change) || ""}
  end

  defp severity_rank("high"), do: 0
  defp severity_rank("medium"), do: 1
  defp severity_rank("low"), do: 2
  defp severity_rank(_), do: 3

  defp details_value(details, key) when is_map(details) do
    Map.get(details, key) || Map.get(details, Atom.to_string(key))
  end

  defp details_value(_details, _key), do: nil
end
