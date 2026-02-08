defmodule PrivSignal.Diff.Severity do
  @moduledoc false

  @default_rule_id "R-LOW-DEFAULT"
  @high_sensitivity_field_names MapSet.new(["ssn", "dob", "date_of_birth", "passport_number"])

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

  defp classify(%{type: "confidence_changed"}) do
    {"low", "R-LOW-CONFIDENCE-ONLY"}
  end

  defp classify(%{type: "flow_changed", change: "external_sink_added"}) do
    {"high", "R-HIGH-EXTERNAL-SINK-ADDED"}
  end

  defp classify(%{type: "flow_changed", change: "external_sink_added_removed"}) do
    {"high", "R-HIGH-EXTERNAL-SINK-CHANGED"}
  end

  defp classify(%{type: "flow_changed", change: "boundary_changed", details: details}) do
    if details_value(details, :after_boundary) == "external" do
      {"high", "R-HIGH-BOUNDARY-EXITS-SYSTEM"}
    else
      {"low", "R-LOW-BOUNDARY-INTERNALIZED"}
    end
  end

  defp classify(%{type: "flow_changed", change: "pii_fields_expanded", details: details}) do
    added_fields =
      details_value(details, :added_fields)
      |> List.wrap()
      |> Enum.map(&normalize_field_name/1)
      |> MapSet.new()

    if MapSet.size(MapSet.intersection(added_fields, @high_sensitivity_field_names)) > 0 do
      {"high", "R-HIGH-PII-EXPANDED-HIGH-SENSITIVITY"}
    else
      {"medium", "R-MEDIUM-PII-EXPANDED"}
    end
  end

  defp classify(%{type: "flow_changed", change: "pii_fields_reduced"}) do
    {"low", "R-LOW-PII-REDUCED"}
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

  defp normalize_field_name(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_field_name(value), do: to_string(value) |> normalize_field_name()
end
