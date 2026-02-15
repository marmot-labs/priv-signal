defmodule PrivSignal.Score.Engine do
  @moduledoc false

  require Logger

  alias PrivSignal.Score.{Buckets, Rules}

  def run(diff, scoring_config) when is_map(diff) and is_map(scoring_config) do
    start = System.monotonic_time()
    Logger.debug("[priv_signal] score engine started")

    weights =
      case Map.get(scoring_config, :weights, %{}) do
        %{values: values} when is_map(values) -> values
        values when is_map(values) -> values
        _ -> Rules.default_weights()
      end

    thresholds =
      case Map.get(scoring_config, :thresholds, %{}) do
        %{low_max: low_max, medium_max: medium_max, high_min: high_min} ->
          %{low_max: low_max, medium_max: medium_max, high_min: high_min}

        values when is_map(values) ->
          values

        _ ->
          Buckets.default_thresholds()
      end

    {points, reasons, summary} = score_changes(Map.get(diff, :changes, []), weights)

    score = Buckets.classify(points, summary.relevant_changes, reasons, thresholds)

    sorted_reasons =
      Enum.sort_by(reasons, fn reason ->
        {Buckets.severity_rank(reason.severity), reason.rule_id, reason.change_id}
      end)

    emit_rule_hits(sorted_reasons)

    report = %{
      score: score,
      points: points,
      summary:
        Map.take(summary, [
          :nodes_added,
          :external_nodes_added,
          :high_sensitivity_changes,
          :transforms_removed,
          :new_external_domains,
          :ignored_changes,
          :relevant_changes,
          :total_changes
        ]),
      reasons: Enum.map(sorted_reasons, &Map.take(&1, [:rule_id, :points, :change_id]))
    }

    duration_ms = duration_ms(start)

    PrivSignal.Telemetry.emit(
      [:priv_signal, :score, :run, :stop],
      %{duration_ms: duration_ms, points: points, reason_count: length(sorted_reasons)},
      %{ok: true, score: score}
    )

    Logger.info("[priv_signal] score engine completed score=#{score} points=#{points}")

    {:ok, report}
  end

  defp score_changes(changes, weights) do
    initial_summary = %{
      nodes_added: 0,
      external_nodes_added: 0,
      high_sensitivity_changes: 0,
      transforms_removed: 0,
      new_external_domains: 0,
      ignored_changes: 0,
      relevant_changes: 0,
      total_changes: length(changes)
    }

    Enum.reduce(changes, {0, [], initial_summary}, fn change,
                                                      {points_acc, reasons_acc, summary_acc} ->
      updated_summary = update_summary(summary_acc, change)

      case Rules.evaluate(change, weights) do
        {:ok, reason} ->
          {points_acc + reason.points, [reason | reasons_acc],
           Map.update!(updated_summary, :relevant_changes, &(&1 + 1))}

        :ignore ->
          {points_acc, reasons_acc, Map.update!(updated_summary, :ignored_changes, &(&1 + 1))}
      end
    end)
  end

  defp update_summary(summary, %{type: "flow_added", details: details}) do
    summary = Map.update!(summary, :nodes_added, &(&1 + 1))

    if details_value(details, :boundary) == "external" do
      Map.update!(summary, :external_nodes_added, &(&1 + 1))
    else
      summary
    end
  end

  defp update_summary(summary, %{change: "external_sink_added"}) do
    Map.update!(summary, :external_nodes_added, &(&1 + 1))
  end

  defp update_summary(summary, %{change: "pii_fields_expanded", details: details}) do
    added_fields = details_value(details, :added_fields) |> List.wrap()

    if high_sensitivity_fields?(added_fields) do
      Map.update!(summary, :high_sensitivity_changes, &(&1 + 1))
    else
      summary
    end
  end

  defp update_summary(summary, _), do: summary

  defp high_sensitivity_fields?(fields) do
    Enum.any?(fields, fn field ->
      normalized =
        field
        |> to_string()
        |> String.trim()
        |> String.downcase()

      normalized in ["ssn", "dob", "date_of_birth", "passport_number"]
    end)
  end

  defp details_value(details, key) when is_map(details) do
    Map.get(details, key) || Map.get(details, Atom.to_string(key))
  end

  defp details_value(_details, _key), do: nil

  defp emit_rule_hits(reasons) do
    reasons
    |> Enum.group_by(& &1.rule_id)
    |> Enum.each(fn {rule_id, hits} ->
      PrivSignal.Telemetry.emit(
        [:priv_signal, :score, :rule_hit],
        %{count: length(hits)},
        %{rule_id: rule_id}
      )
    end)
  end

  defp duration_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end
end
