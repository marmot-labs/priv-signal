defmodule PrivSignal.Diff.Runner do
  @moduledoc false

  require Logger

  alias PrivSignal.Diff.{ArtifactLoader, ContractV2, Normalize, Semantic, SemanticV2, Severity}
  alias PrivSignal.Diff.Render.{Human, JSON}

  def run(options, opts \\ []) when is_map(options) do
    start = System.monotonic_time()
    emit_run_start(options)

    with {:ok, loaded} <- load_artifacts(options, opts),
         {:ok, normalized} <- normalize_artifacts(loaded),
         {:ok, compared} <- compare(normalized, options),
         {:ok, report} <- build_report(loaded, compared) do
      emit_run_stop(start, report, options)
      {:ok, report}
    else
      {:error, reason} ->
        emit_run_error(start, reason, options)
        {:error, reason}
    end
  end

  defp load_artifacts(options, opts) do
    start = System.monotonic_time()

    result =
      ArtifactLoader.load(options,
        git_runner: Keyword.get(opts, :git_runner, &System.cmd/3),
        file_reader: Keyword.get(opts, :file_reader, &File.read/1),
        validator: Keyword.get(opts, :validator, &PrivSignal.Diff.Contract.validate/2)
      )

    duration_ms = duration_ms(start)

    case result do
      {:ok, loaded} ->
        emit_artifact_load(loaded, duration_ms, true)
        {:ok, loaded}

      {:error, reason} ->
        emit_artifact_load(
          %{base: %{"flows" => []}, candidate: %{"flows" => []}},
          duration_ms,
          false
        )

        {:error, reason}
    end
  end

  defp normalize_artifacts(loaded) do
    start = System.monotonic_time()
    base = Normalize.normalize(loaded.base)
    candidate = Normalize.normalize(loaded.candidate)

    PrivSignal.Telemetry.emit(
      [:priv_signal, :diff, :normalize],
      %{
        duration_ms: duration_ms(start),
        flow_count_base: length(base.flows),
        flow_count_candidate: length(candidate.flows)
      },
      %{ok: true}
    )

    {:ok, %{base: base, candidate: candidate}}
  end

  defp compare(normalized, options) do
    start = System.monotonic_time()

    semantic_changes =
      Semantic.compare_normalized(normalized.base, normalized.candidate,
        include_confidence: Map.get(options, :include_confidence?, false)
      )

    annotated_changes = Severity.annotate(semantic_changes)
    events = SemanticV2.from_changes(annotated_changes)

    with {:ok, validation_warnings} <-
           ContractV2.validate_events(events, strict: Map.get(options, :strict?, false)) do
      PrivSignal.Telemetry.emit(
        [:priv_signal, :diff, :semantic, :compare],
        %{
          duration_ms: duration_ms(start),
          change_count: length(annotated_changes),
          event_count: length(events)
        },
        %{
          ok: true,
          include_confidence: Map.get(options, :include_confidence?, false),
          strict_mode: Map.get(options, :strict?, false)
        }
      )

      {:ok, %{changes: annotated_changes, events: events, warnings: validation_warnings}}
    end
  end

  defp build_report(loaded, compared) do
    start = System.monotonic_time()

    metadata =
      loaded.metadata
      |> Map.put(
        :generated_at,
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      )

    report = %{
      metadata: metadata,
      changes: Map.get(compared, :changes, []),
      events: Map.get(compared, :events, []),
      warnings: Map.get(loaded, :warnings, []) ++ Map.get(compared, :warnings, [])
    }

    human = Human.render(report)
    json = JSON.render(report)

    PrivSignal.Telemetry.emit(
      [:priv_signal, :diff, :render],
      %{
        duration_ms: duration_ms(start),
        change_count: length(report.changes),
        event_count: length(report.events)
      },
      %{ok: true}
    )

    {:ok, %{report: report, human: human, json: json}}
  end

  defp emit_artifact_load(loaded, duration_ms, ok?) do
    PrivSignal.Telemetry.emit(
      [:priv_signal, :diff, :artifact, :load],
      %{
        duration_ms: duration_ms,
        flow_count_base: loaded.base |> Map.get("flows", []) |> length(),
        flow_count_candidate: loaded.candidate |> Map.get("flows", []) |> length()
      },
      %{ok: ok?}
    )
  end

  defp emit_run_start(options) do
    PrivSignal.Telemetry.emit(
      [:priv_signal, :diff, :run, :start],
      %{},
      %{
        base_ref: Map.get(options, :base),
        include_confidence: Map.get(options, :include_confidence?, false),
        strict_mode: Map.get(options, :strict?, false)
      }
    )
  end

  defp emit_run_stop(start, result, options) do
    summary = result.json.summary

    PrivSignal.Telemetry.emit(
      [:priv_signal, :diff, :run, :stop],
      %{
        duration_ms: duration_ms(start),
        change_count: summary.events_total,
        high_count: summary.events_high,
        medium_count: summary.events_medium,
        low_count: summary.events_low
      },
      %{
        ok: true,
        format: Map.get(options, :format, :human),
        include_confidence: Map.get(options, :include_confidence?, false),
        schema_version_base: result.report.metadata.schema_version_base,
        schema_version_candidate: result.report.metadata.schema_version_candidate,
        strict_mode: Map.get(options, :strict?, false)
      }
    )

    Logger.info("[priv_signal] diff run completed events=#{summary.events_total}")
  end

  defp emit_run_error(start, reason, options) do
    PrivSignal.Telemetry.emit(
      [:priv_signal, :diff, :run, :error],
      %{duration_ms: duration_ms(start), error_count: 1},
      %{
        ok: false,
        reason: inspect(reason),
        format: Map.get(options, :format, :human),
        include_confidence: Map.get(options, :include_confidence?, false),
        strict_mode: Map.get(options, :strict?, false)
      }
    )

    Logger.error("[priv_signal] diff run failed reason=#{inspect(reason)}")
  end

  defp duration_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end
end
