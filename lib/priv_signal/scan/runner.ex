defmodule PrivSignal.Scan.Runner do
  @moduledoc false

  alias PrivSignal.Scan.{Classifier, Inventory, Source}
  alias PrivSignal.Scan.Logger, as: ScanLogger
  require Logger

  @scanner_version "1"
  @default_timeout_ms 5_000
  @max_concurrency_cap 8

  def run(config, opts \\ []) do
    strict? = Keyword.get(opts, :strict, false)
    timeout = resolve_timeout_ms(opts)
    max_concurrency = resolve_max_concurrency(opts)
    scan_fun = Keyword.get(opts, :scan_fun, &ScanLogger.scan_file/2)
    source_opts = Keyword.get(opts, :source, [])

    Logger.debug(
      "[priv_signal] scan run starting strict_mode=#{strict?} timeout_ms=#{timeout} max_concurrency=#{max_concurrency}"
    )

    {inventory_duration_ms, inventory} = timed(fn -> Inventory.build(config) end)
    files = Source.files(source_opts)

    emit_inventory_telemetry(inventory, inventory_duration_ms)

    {:ok, supervisor} = Task.Supervisor.start_link()

    {duration_ms, {candidates, errors}} =
      timed(fn ->
        Task.Supervisor.async_stream_nolink(
          supervisor,
          files,
          fn file -> scan_file(file, inventory, scan_fun) end,
          max_concurrency: max_concurrency,
          timeout: timeout,
          on_timeout: :kill_task,
          ordered: false
        )
        |> Enum.reduce({[], []}, fn result, {finding_acc, error_acc} ->
          merge_worker_result(result, finding_acc, error_acc)
        end)
      end)

    findings =
      candidates
      |> Classifier.classify()
      |> Classifier.stable_sort()

    result = %{
      scanner_version: @scanner_version,
      summary: %{
        confirmed_count: Enum.count(findings, &(&1.classification == :confirmed_pii)),
        possible_count: Enum.count(findings, &(&1.classification == :possible_pii)),
        high_sensitivity_count: Enum.count(findings, &(&1.sensitivity == :high)),
        files_scanned: length(files),
        errors: length(errors)
      },
      inventory: %{
        modules: inventory.modules |> MapSet.to_list() |> Enum.sort(),
        field_count: length(inventory.fields)
      },
      findings: findings,
      errors: Enum.sort_by(errors, &{&1.file || "", &1.reason || ""})
    }

    emit_run_telemetry(result, duration_ms, strict?)
    log_run_result(result, strict?)

    if strict? and result.summary.errors > 0 do
      Logger.error("[priv_signal] scan strict mode failed error_count=#{result.summary.errors}")
      {:error, {:strict_mode_failed, result}}
    else
      {:ok, result}
    end
  end

  defp scan_file(file, inventory, scan_fun) do
    case scan_fun.(file, inventory) do
      {:ok, findings} -> {:ok, file, findings}
      {:error, reason} -> {:error, file, reason}
    end
  end

  defp merge_worker_result({:ok, {:ok, _file, findings}}, finding_acc, error_acc) do
    {findings ++ finding_acc, error_acc}
  end

  defp merge_worker_result({:ok, {:error, file, reason}}, finding_acc, error_acc) do
    {finding_acc, [%{file: file, reason: format_reason(reason), type: :parse_error} | error_acc]}
  end

  defp merge_worker_result({:exit, :timeout}, finding_acc, error_acc) do
    {finding_acc, [%{file: nil, reason: "scan worker timed out", type: :timeout} | error_acc]}
  end

  defp merge_worker_result({:exit, reason}, finding_acc, error_acc) do
    {finding_acc,
     [
       %{file: nil, reason: "worker_exit: #{format_reason(reason)}", type: :worker_exit}
       | error_acc
     ]}
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp default_max_concurrency do
    System.schedulers_online()
    |> min(8)
    |> max(1)
  end

  defp resolve_timeout_ms(opts) do
    value = Keyword.get(opts, :timeout) || System.get_env("PRIV_SIGNAL_SCAN_TIMEOUT_MS")
    timeout = parse_positive_integer(value, @default_timeout_ms)
    max(timeout, 100)
  end

  defp resolve_max_concurrency(opts) do
    value =
      Keyword.get(opts, :max_concurrency) || System.get_env("PRIV_SIGNAL_SCAN_MAX_CONCURRENCY")

    value
    |> parse_positive_integer(default_max_concurrency())
    |> min(@max_concurrency_cap)
    |> max(1)
  end

  defp parse_positive_integer(nil, default), do: default
  defp parse_positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp parse_positive_integer(_value, default), do: default

  defp timed(fun) do
    start = System.monotonic_time()
    value = fun.()

    duration_ms =
      System.monotonic_time()
      |> Kernel.-(start)
      |> System.convert_time_unit(:native, :millisecond)

    {duration_ms, value}
  end

  defp emit_inventory_telemetry(inventory, duration_ms) do
    PrivSignal.Telemetry.emit(
      [:priv_signal, :scan, :inventory, :build],
      %{duration_ms: duration_ms},
      %{module_count: MapSet.size(inventory.modules), field_count: length(inventory.fields)}
    )
  end

  defp emit_run_telemetry(result, duration_ms, strict?) do
    error_counts = error_type_counts(result.errors)

    PrivSignal.Telemetry.emit(
      [:priv_signal, :scan, :run],
      %{
        duration_ms: duration_ms,
        file_count: result.summary.files_scanned,
        finding_count: length(result.findings),
        confirmed_count: result.summary.confirmed_count,
        possible_count: result.summary.possible_count,
        error_count: result.summary.errors
      },
      %{
        ok: result.summary.errors == 0,
        strict_mode: strict?,
        scanner_version: result.scanner_version,
        timeout_count: error_counts.timeout,
        parse_error_count: error_counts.parse_error,
        worker_exit_count: error_counts.worker_exit
      }
    )
  end

  defp log_run_result(result, strict?) do
    error_counts = error_type_counts(result.errors)

    Logger.info(
      "[priv_signal] scan run completed files=#{result.summary.files_scanned} findings=#{length(result.findings)} strict_mode=#{strict?}"
    )

    if result.summary.errors > 0 do
      Logger.warning(
        "[priv_signal] scan run completed with errors total=#{result.summary.errors} parse=#{error_counts.parse_error} timeout=#{error_counts.timeout} worker_exit=#{error_counts.worker_exit}"
      )
    end
  end

  defp error_type_counts(errors) do
    Enum.reduce(errors, %{parse_error: 0, timeout: 0, worker_exit: 0}, fn error, acc ->
      case error[:type] do
        :parse_error -> %{acc | parse_error: acc.parse_error + 1}
        :timeout -> %{acc | timeout: acc.timeout + 1}
        :worker_exit -> %{acc | worker_exit: acc.worker_exit + 1}
        _ -> acc
      end
    end)
  end
end
