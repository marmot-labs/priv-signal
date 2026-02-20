defmodule PrivSignal.Scan.Runner do
  @moduledoc false

  alias PrivSignal.Scan.{Classifier, Inventory, Source}
  alias PrivSignal.Scan.Scanner
  alias PrivSignal.Scan.Scanner.Cache, as: ScannerCache
  alias PrivSignal.Scan.Scanner.Controller, as: ControllerScanner
  alias PrivSignal.Scan.Scanner.Database, as: DatabaseScanner
  alias PrivSignal.Scan.Scanner.HTTP, as: HTTPScanner
  alias PrivSignal.Scan.Scanner.LiveView, as: LiveViewScanner
  alias PrivSignal.Scan.Scanner.Logging, as: LoggingScanner
  alias PrivSignal.Scan.Scanner.Telemetry, as: TelemetryScanner
  alias PrivSignal.Validate.AST
  require Logger

  @scanner_version "1"
  @default_timeout_ms 5_000
  @max_concurrency_cap 8

  def run(config, opts \\ []) do
    strict? = Keyword.get(opts, :strict, false)
    timeout = resolve_timeout_ms(opts)
    max_concurrency = resolve_max_concurrency(opts)

    opts =
      Keyword.put_new(
        opts,
        :scanner_config,
        config.scanners || PrivSignal.Config.default_scanners()
      )

    scan_fun = Keyword.get(opts, :scan_fun)
    parse_fun = Keyword.get(opts, :parse_fun, &AST.parse_file/1)
    scanner_modules = resolve_scanner_modules(config, opts)
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
          fn file ->
            scan_file(file, inventory, scan_fun, parse_fun, scanner_modules, opts)
          end,
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
        confirmed_count: Enum.count(findings, &(&1.classification == :confirmed_prd)),
        possible_count: Enum.count(findings, &(&1.classification == :possible_prd)),
        high_sensitivity_count: Enum.count(findings, &(&1.sensitivity == :high)),
        class_counts: class_counts(findings),
        files_scanned: length(files),
        scan_duration_ms: duration_ms,
        errors: length(errors)
      },
      inventory: %{
        modules: inventory.modules |> MapSet.to_list() |> Enum.sort(),
        node_count: length(inventory.data_nodes),
        data_nodes: inventory.data_nodes
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

  defp scan_file(file, inventory, scan_fun, parse_fun, scanner_modules, opts) do
    if is_function(scan_fun, 2) do
      case scan_fun.(file, inventory) do
        {:ok, findings} -> {:ok, file, findings}
        {:error, reason} -> {:error, file, reason}
      end
    else
      case parse_fun.(file) do
        {:ok, ast} ->
          file_ctx = %{path: file, cache: ScannerCache.build(ast, file)}

          candidates =
            scan_with_modules(
              ast,
              file_ctx,
              inventory,
              scanner_modules,
              config_scanner_opts(opts)
            )

          {:ok, file, candidates}

        {:error, reason} ->
          {:error, file, reason}
      end
    end
  end

  defp scan_with_modules(ast, file_ctx, inventory, scanner_modules, opts) do
    scanner_opts = Keyword.put(opts, :file_cache, file_ctx.cache)

    scanner_modules
    |> Enum.flat_map(fn scanner ->
      category = scanner_category(scanner)

      {duration_ms, findings} =
        timed(fn ->
          scanner.scan_ast(ast, file_ctx, inventory, scanner_opts)
        end)

      emit_category_telemetry(category, duration_ms, findings)
      findings
    end)
  end

  defp config_scanner_opts(opts) do
    opts
  end

  defp resolve_scanner_modules(config, opts) do
    case Keyword.get(opts, :scanner_modules) do
      nil ->
        config
        |> scanner_modules_from_config()
        |> Enum.filter(&Scanner.valid_module?/1)
        |> case do
          [] -> [LoggingScanner]
          modules -> modules
        end

      override ->
        override
        |> List.wrap()
        |> Enum.filter(&Scanner.valid_module?/1)
        |> case do
          [] -> [LoggingScanner]
          modules -> modules
        end
    end
  end

  defp scanner_modules_from_config(config) do
    scanners = Map.get(config, :scanners) || PrivSignal.Config.default_scanners()

    []
    |> maybe_add_scanner(scanners.logging, LoggingScanner)
    |> maybe_add_scanner(scanners.http, HTTPScanner)
    |> maybe_add_scanner(scanners.controller, ControllerScanner)
    |> maybe_add_scanner(scanners.telemetry, TelemetryScanner)
    |> maybe_add_scanner(scanners.database, DatabaseScanner)
    |> maybe_add_scanner(scanners.liveview, LiveViewScanner)
  end

  defp maybe_add_scanner(modules, nil, _module), do: modules

  defp maybe_add_scanner(modules, scanner_cfg, module) do
    if Map.get(scanner_cfg, :enabled, true) do
      modules ++ [module]
    else
      modules
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
      %{module_count: MapSet.size(inventory.modules), node_count: length(inventory.data_nodes)}
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

  defp emit_category_telemetry(category, duration_ms, findings) do
    by_role_kind =
      findings
      |> Enum.map(&Map.get(&1, :role_kind, "logger"))
      |> Enum.map(&to_string/1)
      |> Enum.frequencies()

    PrivSignal.Telemetry.emit(
      [:priv_signal, :scan, :category, :run],
      %{duration_ms: duration_ms, finding_count: length(findings)},
      %{category: category, enabled: true, error_count: 0}
    )

    Enum.each(by_role_kind, fn {role_kind, count} ->
      PrivSignal.Telemetry.emit(
        [:priv_signal, :scan, :candidate, :emit],
        %{count: count},
        %{node_type: node_type_for_role_kind(role_kind), role_kind: role_kind}
      )
    end)
  end

  defp log_run_result(result, strict?) do
    error_counts = error_type_counts(result.errors)

    role_kind_counts =
      result.findings
      |> Enum.map(&Map.get(&1, :role_kind, "logger"))
      |> Enum.map(&to_string/1)
      |> Enum.frequencies()
      |> Enum.sort()
      |> Enum.map_join(",", fn {kind, count} -> "#{kind}:#{count}" end)

    Logger.info(
      "[priv_signal] scan run completed files=#{result.summary.files_scanned} findings=#{length(result.findings)} strict_mode=#{strict?} role_kinds=#{role_kind_counts}"
    )

    if result.summary.errors > 0 do
      Logger.warning(
        "[priv_signal] scan run completed with errors total=#{result.summary.errors} parse=#{error_counts.parse_error} timeout=#{error_counts.timeout} worker_exit=#{error_counts.worker_exit}"
      )
    end
  end

  defp scanner_category(scanner) do
    scanner
    |> Module.split()
    |> List.last()
    |> to_string()
    |> String.downcase()
  end

  defp node_type_for_role_kind("database_read"), do: "source"
  defp node_type_for_role_kind(_), do: "sink"

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

  defp class_counts(findings) do
    findings
    |> Enum.flat_map(&(&1.data_classes || []))
    |> Enum.frequencies()
    |> Enum.sort()
    |> Map.new()
  end
end
