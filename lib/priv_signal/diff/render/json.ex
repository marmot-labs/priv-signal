defmodule PrivSignal.Diff.Render.JSON do
  @moduledoc false

  @schema_version "v1"

  def schema_version, do: @schema_version

  def render(report) when is_map(report) do
    changes =
      report
      |> Map.get(:changes, [])
      |> Enum.map(&normalize_change/1)
      |> Enum.sort_by(&change_sort_key/1)

    %{
      version: @schema_version,
      metadata: Map.get(report, :metadata, %{}),
      summary: summary(changes),
      changes: changes
    }
  end

  defp summary(changes) do
    counts =
      Enum.reduce(changes, %{high: 0, medium: 0, low: 0}, fn change, acc ->
        case Map.get(change, :severity) do
          "high" -> Map.update!(acc, :high, &(&1 + 1))
          "medium" -> Map.update!(acc, :medium, &(&1 + 1))
          "low" -> Map.update!(acc, :low, &(&1 + 1))
          _ -> acc
        end
      end)

    Map.put(counts, :total, length(changes))
  end

  defp normalize_change(change) when is_map(change) do
    %{
      type: Map.get(change, :type) || Map.get(change, "type"),
      flow_id: Map.get(change, :flow_id) || Map.get(change, "flow_id"),
      change: Map.get(change, :change) || Map.get(change, "change"),
      severity: Map.get(change, :severity) || Map.get(change, "severity"),
      rule_id: Map.get(change, :rule_id) || Map.get(change, "rule_id"),
      details: Map.get(change, :details) || Map.get(change, "details") || %{}
    }
  end

  defp change_sort_key(change) do
    {severity_rank(change.severity), change.flow_id || "", change.type || "", change.change || ""}
  end

  defp severity_rank("high"), do: 0
  defp severity_rank("medium"), do: 1
  defp severity_rank("low"), do: 2
  defp severity_rank(_), do: 3
end
