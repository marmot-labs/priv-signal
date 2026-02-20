defmodule PrivSignal.Validate do
  @moduledoc false

  alias PrivSignal.Validate.{Error, Index, Result}
  require Logger

  @doc """
  Validates configured PRD node scope modules against source.
  """
  def run(config, opts \\ []) do
    index_opts = Keyword.get(opts, :index, [])
    prd_modules = PrivSignal.Config.PRD.modules(config)
    flow_count = 1
    # Build one index per run to keep validation deterministic and fast.
    start = System.monotonic_time()

    Logger.debug("[priv_signal] validate run starting flow_count=#{flow_count}")

    result =
      with {:ok, index} <- Index.build(index_opts) do
        prd_result = validate_prd_modules(prd_modules, index)
        {:ok, [prd_result]}
      end

    log_run_result(result, flow_count)
    emit_run_telemetry(result, start, flow_count)

    result
  end

  def status(results) do
    if Enum.all?(results, &Result.ok?/1), do: :ok, else: :error
  end

  defp validate_prd_modules(prd_modules, index) do
    errors =
      prd_modules
      |> Enum.map(&normalize_module/1)
      |> Enum.uniq()
      |> Enum.reduce([], fn module, acc ->
        if module_exists?(index, module) do
          acc
        else
          [Error.missing_prd_module(module) | acc]
        end
      end)
      |> Enum.reverse()

    status = if errors == [], do: :ok, else: :error
    %Result{flow_id: "prd_nodes", status: status, errors: errors}
  end

  defp module_exists?(index, module) when is_binary(module) do
    MapSet.member?(index.modules, module)
  end

  defp module_exists?(_index, _module), do: false

  defp normalize_module("Elixir." <> rest), do: rest
  defp normalize_module(module), do: module

  defp log_run_result({:ok, results}, flow_count) do
    # Log outcomes at different levels so CI and operators can triage quickly.
    stats = result_stats(results)

    if stats.status == :ok do
      Logger.info(
        "[priv_signal] validate run ok flow_count=#{flow_count} error_count=#{stats.error_count}"
      )
    else
      Logger.error(
        "[priv_signal] validate run failed flow_count=#{flow_count} error_count=#{stats.error_count}"
      )
    end
  end

  defp log_run_result({:error, errors}, flow_count) do
    # Index failures are fatal for validation, so log as error.
    Logger.error(
      "[priv_signal] validate run failed flow_count=#{flow_count} error_count=#{length(errors)}"
    )
  end

  defp emit_run_telemetry({:ok, results}, start, flow_count) do
    # Emit summarized counts so telemetry stays deterministic and low-volume.
    stats = result_stats(results)

    PrivSignal.Telemetry.emit(
      [:priv_signal, :validate, :run],
      %{duration_ms: duration_ms(start)},
      %{
        ok: stats.status == :ok,
        status: stats.status,
        flow_count: flow_count,
        error_count: stats.error_count,
        ambiguous_count: stats.ambiguous_count
      }
    )
  end

  defp emit_run_telemetry({:error, errors}, start, flow_count) do
    # Preserve failure context in telemetry without embedding sensitive details.
    PrivSignal.Telemetry.emit(
      [:priv_signal, :validate, :run],
      %{duration_ms: duration_ms(start)},
      %{ok: false, status: :error, flow_count: flow_count, error_count: length(errors)}
    )
  end

  defp result_stats(results) do
    # Summarize errors to avoid leaking detailed flow config in telemetry.
    errors = Enum.flat_map(results, & &1.errors)

    %{
      status: status(results),
      error_count: length(errors),
      ambiguous_count: 0
    }
  end

  defp duration_ms(start) do
    # Standardize duration reporting for telemetry consumers.
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end
end
