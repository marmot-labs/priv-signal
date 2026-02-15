defmodule PrivSignal.Score.Rules do
  @moduledoc false

  alias PrivSignal.Score.Defaults

  @high_sensitivity_field_names MapSet.new(["ssn", "dob", "date_of_birth", "passport_number"])

  def default_weights, do: Defaults.weights()

  def evaluate(change, weights \\ default_weights()) when is_map(change) and is_map(weights) do
    with {:ok, rule_id} <- resolve_rule_id(change),
         points when is_integer(points) <- Map.get(weights, rule_id, 0) do
      reason = %{
        rule_id: rule_id,
        points: points,
        change_id: "flow:#{change.flow_id}:#{change.change}",
        severity: resolve_severity(change, rule_id)
      }

      {:ok, reason}
    else
      :ignore -> :ignore
      _ -> :ignore
    end
  end

  defp resolve_rule_id(%{rule_id: rule_id}) when is_binary(rule_id) and rule_id != "",
    do: {:ok, rule_id}

  defp resolve_rule_id(%{type: "flow_added", details: details}) do
    if details_value(details, :boundary) == "external" do
      {:ok, "R-HIGH-EXTERNAL-FLOW-ADDED"}
    else
      {:ok, "R-MEDIUM-INTERNAL-FLOW-ADDED"}
    end
  end

  defp resolve_rule_id(%{type: "flow_removed"}), do: {:ok, "R-LOW-FLOW-REMOVED"}
  defp resolve_rule_id(%{type: "confidence_changed"}), do: {:ok, "R-LOW-CONFIDENCE-ONLY"}

  defp resolve_rule_id(%{type: "flow_changed", change: "external_sink_added"}),
    do: {:ok, "R-HIGH-EXTERNAL-SINK-ADDED"}

  defp resolve_rule_id(%{type: "flow_changed", change: "external_sink_added_removed"}),
    do: {:ok, "R-HIGH-EXTERNAL-SINK-CHANGED"}

  defp resolve_rule_id(%{type: "flow_changed", change: "boundary_changed", details: details}) do
    if details_value(details, :after_boundary) == "external" do
      {:ok, "R-HIGH-BOUNDARY-EXITS-SYSTEM"}
    else
      {:ok, "R-LOW-BOUNDARY-INTERNALIZED"}
    end
  end

  defp resolve_rule_id(%{type: "flow_changed", change: "pii_fields_expanded", details: details}) do
    added_fields =
      details_value(details, :added_fields)
      |> List.wrap()
      |> Enum.map(&normalize_field_name/1)
      |> MapSet.new()

    if MapSet.size(MapSet.intersection(added_fields, @high_sensitivity_field_names)) > 0 do
      {:ok, "R-HIGH-PII-EXPANDED-HIGH-SENSITIVITY"}
    else
      {:ok, "R-MEDIUM-PII-EXPANDED"}
    end
  end

  defp resolve_rule_id(%{type: "flow_changed", change: "pii_fields_reduced"}),
    do: {:ok, "R-LOW-PII-REDUCED"}

  defp resolve_rule_id(_), do: :ignore

  defp resolve_severity(%{severity: severity}, _rule_id)
       when severity in ["high", "medium", "low"],
       do: severity

  defp resolve_severity(_change, rule_id) do
    cond do
      String.starts_with?(rule_id, "R-HIGH") -> "high"
      String.starts_with?(rule_id, "R-MEDIUM") -> "medium"
      true -> "low"
    end
  end

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
