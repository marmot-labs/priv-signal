defmodule PrivSignal.Infer.Runner do
  @moduledoc false

  alias PrivSignal.Infer.{Contract, FlowBuilder}
  alias PrivSignal.Infer.ScannerAdapter.Logging, as: LoggingAdapter
  alias PrivSignal.Scan.Runner, as: ScanRunner

  @tool_name "priv_signal"

  def run(config, opts \\ []) do
    start = System.monotonic_time()
    strict? = Keyword.get(opts, :strict, false)
    proto_flows_enabled? = proto_flows_enabled?(opts)

    emit_run_start(strict?, proto_flows_enabled?)

    scan_opts =
      opts
      |> Keyword.take([:strict, :timeout, :max_concurrency, :source, :scan_fun])

    case ScanRunner.run(config, scan_opts) do
      {:ok, scan_result} ->
        result = build_infer_result(scan_result, opts, proto_flows_enabled?)
        emit_run_stop(result, start, strict?, proto_flows_enabled?, true)
        {:ok, result}

      {:error, {:strict_mode_failed, scan_result}} ->
        result = build_infer_result(scan_result, opts, proto_flows_enabled?)
        emit_run_stop(result, start, strict?, proto_flows_enabled?, false)
        {:error, {:strict_mode_failed, result}}
    end
  end

  defp build_infer_result(scan_result, opts, proto_flows_enabled?) do
    findings = Map.get(scan_result, :findings, [])

    nodes =
      findings
      |> LoggingAdapter.from_findings(
        root: File.cwd!(),
        emit_entrypoint_nodes: emit_entrypoint_nodes?()
      )
      |> Contract.stable_sort_nodes()

    {flows, candidate_count} =
      if proto_flows_enabled? do
        {flow_duration_ms, flow_build} =
          timed(fn ->
            FlowBuilder.build(nodes, Keyword.take(opts, [:weights]))
          end)

        built_flows = Map.get(flow_build, :flows, [])
        built_candidate_count = Map.get(flow_build, :candidate_count, 0)

        emit_flow_build_telemetry(
          nodes,
          built_flows,
          built_candidate_count,
          flow_duration_ms,
          proto_flows_enabled?
        )

        {built_flows, built_candidate_count}
      else
        emit_flow_build_telemetry(nodes, [], 0, 0, proto_flows_enabled?)
        {[], 0}
      end

    %{
      schema_version: Contract.schema_version(),
      tool: %{
        name: @tool_name,
        version: tool_version()
      },
      git: %{
        commit: git_commit()
      },
      summary: build_summary(scan_result, nodes, flows, candidate_count, proto_flows_enabled?),
      nodes: nodes,
      flows: flows,
      errors: Map.get(scan_result, :errors, [])
    }
  end

  defp build_summary(scan_result, nodes, flows, candidate_count, proto_flows_enabled?) do
    summary = Map.get(scan_result, :summary, %{})
    flows_hash = flows_hash(flows)

    %{
      node_count: length(nodes),
      flow_count: length(flows),
      flow_candidate_count: candidate_count,
      flows_hash: flows_hash,
      proto_flows_enabled: proto_flows_enabled?,
      node_type_counts: count_by(nodes, &Map.get(&1, :node_type)),
      boundary_counts: count_by(flows, &Map.get(&1, :boundary)),
      files_scanned: Map.get(summary, :files_scanned, 0),
      scan_error_count: Map.get(summary, :errors, 0),
      confirmed_count: Map.get(summary, :confirmed_count, 0),
      possible_count: Map.get(summary, :possible_count, 0)
    }
  end

  defp count_by(list, fun) do
    Enum.reduce(list, %{}, fn item, acc ->
      key = fun.(item)
      Map.update(acc, key, 1, &(&1 + 1))
    end)
  end

  defp emit_run_start(strict?, proto_flows_enabled?) do
    PrivSignal.Telemetry.emit(
      [:priv_signal, :infer, :run, :start],
      %{},
      %{strict_mode: strict?, proto_flows_enabled: proto_flows_enabled?}
    )
  end

  defp emit_flow_build_telemetry(nodes, flows, candidate_count, duration_ms, proto_flows_enabled?) do
    entrypoint_kinds =
      nodes
      |> Enum.filter(&(&1.node_type == "entrypoint"))
      |> Enum.map(fn node ->
        node
        |> Map.get(:role, %{})
        |> Map.get(:kind, "unknown")
      end)
      |> Enum.uniq()
      |> Enum.sort()

    PrivSignal.Telemetry.emit(
      [:priv_signal, :infer, :flow, :build],
      %{
        duration_ms: duration_ms,
        node_count: length(nodes),
        candidate_count: candidate_count,
        flow_count: length(flows)
      },
      %{
        entrypoint_kinds_present: entrypoint_kinds,
        boundary_counts: count_by(flows, &Map.get(&1, :boundary)),
        proto_flows_enabled: proto_flows_enabled?
      }
    )
  end

  defp emit_run_stop(result, start, strict?, proto_flows_enabled?, ok?) do
    duration_ms =
      System.monotonic_time()
      |> Kernel.-(start)
      |> System.convert_time_unit(:native, :millisecond)

    summary = Map.get(result, :summary, %{})
    flows = Map.get(result, :flows, [])

    PrivSignal.Telemetry.emit(
      [:priv_signal, :infer, :run, :stop],
      %{
        duration_ms: duration_ms,
        node_count: Map.get(summary, :node_count, 0),
        flow_count: Map.get(summary, :flow_count, 0),
        candidate_count: Map.get(summary, :flow_candidate_count, 0),
        error_count: Map.get(summary, :scan_error_count, 0)
      },
      %{
        ok: ok?,
        strict_mode: strict?,
        proto_flows_enabled: proto_flows_enabled?,
        schema_version: Map.get(result, :schema_version),
        determinism_hash_changed: 0,
        boundary_counts: count_by(flows, &Map.get(&1, :boundary))
      }
    )
  end

  defp emit_entrypoint_nodes? do
    case System.get_env("PRIV_SIGNAL_INFER_EMIT_ENTRYPOINT_NODES") do
      value when value in ["1", "true", "TRUE", "yes", "YES"] -> true
      _ -> false
    end
  end

  defp tool_version do
    case Application.spec(:priv_signal, :vsn) do
      nil -> Mix.Project.config()[:version] || "unknown"
      vsn when is_list(vsn) -> List.to_string(vsn)
      vsn when is_binary(vsn) -> vsn
      _ -> "unknown"
    end
  end

  defp git_commit do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp proto_flows_enabled?(opts) do
    case Keyword.get(opts, :proto_flows_enabled) do
      value when is_boolean(value) ->
        value

      _ ->
        case System.get_env("PRIV_SIGNAL_INFER_PROTO_FLOWS_V1", "true") do
          value when value in ["0", "false", "FALSE", "no", "NO"] -> false
          _ -> true
        end
    end
  end

  defp flows_hash(flows) when is_list(flows) do
    flows
    |> Contract.stable_sort_flows()
    |> Enum.map(fn flow ->
      sink = Map.get(flow, :sink, %{})

      %{
        id: Map.get(flow, :id),
        source: Map.get(flow, :source),
        entrypoint: Map.get(flow, :entrypoint),
        sink_kind: Map.get(sink, :kind),
        sink_subtype: Map.get(sink, :subtype),
        boundary: Map.get(flow, :boundary),
        confidence: Map.get(flow, :confidence),
        evidence: Map.get(flow, :evidence, [])
      }
    end)
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  defp timed(fun) do
    start = System.monotonic_time()
    value = fun.()

    duration_ms =
      System.monotonic_time()
      |> Kernel.-(start)
      |> System.convert_time_unit(:native, :millisecond)

    {duration_ms, value}
  end
end
