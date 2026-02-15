defmodule PrivSignal.Score.Buckets do
  @moduledoc false

  alias PrivSignal.Score.Defaults

  def default_thresholds, do: Defaults.thresholds()

  def classify(points, relevant_changes, reasons, thresholds \\ default_thresholds())
      when is_integer(points) and is_integer(relevant_changes) and is_list(reasons) and
             is_map(thresholds) do
    base_bucket = base_bucket(points, relevant_changes, thresholds)
    apply_floor_escalation(base_bucket, reasons)
  end

  def severity_rank("high"), do: 0
  def severity_rank("medium"), do: 1
  def severity_rank("low"), do: 2
  def severity_rank(_), do: 3

  defp base_bucket(_points, 0, _thresholds), do: "NONE"

  defp base_bucket(points, _relevant_changes, thresholds) do
    low_max = Map.get(thresholds, :low_max, 3)
    medium_max = Map.get(thresholds, :medium_max, 8)

    cond do
      points <= low_max -> "LOW"
      points <= medium_max -> "MEDIUM"
      true -> "HIGH"
    end
  end

  defp apply_floor_escalation(bucket, reasons) do
    cond do
      has_rule?(reasons, [
        "R-HIGH-EXTERNAL-FLOW-ADDED",
        "R-HIGH-EXTERNAL-SINK-ADDED",
        "R-HIGH-EXTERNAL-SINK-CHANGED"
      ]) ->
        "HIGH"

      has_rule?(reasons, [
        "R-HIGH-BOUNDARY-EXITS-SYSTEM",
        "R-HIGH-PII-EXPANDED-HIGH-SENSITIVITY",
        "R-MEDIUM-PII-EXPANDED"
      ]) ->
        floor_to(bucket, "MEDIUM")

      true ->
        bucket
    end
  end

  defp has_rule?(reasons, rule_ids) do
    Enum.any?(reasons, fn reason -> reason.rule_id in rule_ids end)
  end

  defp floor_to("NONE", target), do: target
  defp floor_to("LOW", target), do: target
  defp floor_to(bucket, _target), do: bucket
end
