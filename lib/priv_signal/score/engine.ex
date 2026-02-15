defmodule PrivSignal.Score.Engine do
  @moduledoc false

  require Logger

  alias PrivSignal.Score.RubricV2

  def run(diff, scoring_config) when is_map(diff) and is_map(scoring_config) do
    _ = scoring_config
    run_v2(diff)
  end

  defp run_v2(diff) do
    start = System.monotonic_time()
    Logger.debug("[priv_signal] score_engine_start version=v2")

    strict? = diff |> Map.get(:metadata, %{}) |> Map.get(:strict_mode, false)

    with {:ok, events} <- require_events(diff),
         {:ok, classified_events, warnings} <- RubricV2.classify_events(events, strict: strict?) do
      summary = build_v2_summary(classified_events, warnings)
      score = decide_v2_score(summary)
      reasons = v2_reasons(classified_events, score)
      emit_rule_hits(reasons)

      duration_ms = duration_ms(start)

      PrivSignal.Telemetry.emit(
        [:priv_signal, :score, :run, :stop],
        %{duration_ms: duration_ms, reason_count: length(reasons)},
        %{ok: true, score: score, version: "v2", strict_mode: strict?}
      )

      Logger.info(
        "[priv_signal] score_decision version=v2 score=#{score} events_total=#{summary.events_total} events_high=#{summary.events_high} events_medium=#{summary.events_medium} events_low=#{summary.events_low} reasons_count=#{length(reasons)}"
      )

      {:ok, %{score: score, summary: summary, reasons: reasons}}
    else
      {:error, reason} ->
        Logger.error(
          "[priv_signal] score_contract_error version=v2 reason=#{sanitize_reason(reason)}"
        )

        {:error, reason}
    end
  end

  defp require_events(diff) do
    case Map.get(diff, :events) do
      events when is_list(events) -> {:ok, events}
      _ -> {:error, {:unsupported_score_input, %{required: "diff.version=v2 with events[]"}}}
    end
  end

  defp build_v2_summary(events, warnings) do
    %{
      events_total: length(events),
      events_high: Enum.count(events, &(&1.event_class == "high")),
      events_medium: Enum.count(events, &(&1.event_class == "medium")),
      events_low: Enum.count(events, &(&1.event_class == "low")),
      unknown_events: Enum.count(events, &Map.get(&1, :unknown_event_type, false)),
      warnings_count: length(warnings)
    }
  end

  defp decide_v2_score(summary) do
    cond do
      summary.events_total == 0 -> "NONE"
      summary.events_high > 0 -> "HIGH"
      summary.events_medium > 0 -> "MEDIUM"
      true -> "LOW"
    end
  end

  defp v2_reasons(events, score) do
    target_class =
      case score do
        "HIGH" -> "high"
        "MEDIUM" -> "medium"
        "LOW" -> "low"
        _ -> nil
      end

    events
    |> Enum.filter(fn event -> target_class != nil and event.event_class == target_class end)
    |> Enum.map(&Map.take(&1, [:event_id, :rule_id]))
    |> Enum.sort_by(fn reason -> {reason.rule_id || "", reason.event_id || ""} end)
  end

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

  defp sanitize_reason({:unknown_event_type, _}), do: "unknown_event_type"
  defp sanitize_reason({:unsupported_score_input, _}), do: "unsupported_score_input"
  defp sanitize_reason({:invalid_event, _}), do: "invalid_event"
  defp sanitize_reason(_), do: "contract_error"

  defp duration_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end
end
