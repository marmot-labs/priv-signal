defmodule PrivSignal.Validate do
  @moduledoc false

  alias PrivSignal.Config.PathStep
  alias PrivSignal.Validate.{Error, Index, Result}
  require Logger

  @doc """
  Validates all configured flows against a single source index so scoring can fail fast
  when declared modules/functions drift from code.
  """
  def run(config, opts \\ []) do
    index_opts = Keyword.get(opts, :index, [])
    pii_modules = PrivSignal.Config.PII.modules(config)
    flows = config.flows || []
    flow_count = length(flows) + 1
    # Build one index per run to keep validation deterministic and fast.
    start = System.monotonic_time()

    Logger.debug("[priv_signal] validate run starting flow_count=#{flow_count}")

    result =
      with {:ok, index} <- Index.build(index_opts) do
        pii_result = validate_pii_modules(pii_modules, index)
        flow_results = Enum.map(flows, &validate_flow(&1, index))
        results = [pii_result | flow_results]
        {:ok, results}
      end

    log_run_result(result, flow_count)
    emit_run_telemetry(result, start, flow_count)

    result
  end

  def status(results) do
    if Enum.all?(results, &Result.ok?/1), do: :ok, else: :error
  end

  def validate_flow(flow, index) do
    flow_id = flow.id || "unknown_flow"
    steps = Enum.map(flow.path || [], &normalize_step/1)

    {module_errors, missing_modules} = validate_modules(steps, index, flow_id)

    {function_errors, _missing_functions} =
      validate_functions(steps, index, flow_id, missing_modules)

    errors = module_errors ++ function_errors
    status = if errors == [], do: :ok, else: :error

    %Result{flow_id: flow_id, status: status, errors: errors}
  end

  defp validate_pii_modules(pii_modules, index) do
    errors =
      pii_modules
      |> Enum.map(&normalize_module/1)
      |> Enum.uniq()
      |> Enum.reduce([], fn module, acc ->
        if module_exists?(index, module) do
          acc
        else
          [Error.missing_pii_module(module) | acc]
        end
      end)
      |> Enum.reverse()

    status = if errors == [], do: :ok, else: :error
    %Result{flow_id: "pii", status: status, errors: errors}
  end

  defp validate_modules(steps, index, flow_id) do
    {errors, missing_modules} =
      Enum.reduce(steps, {[], MapSet.new()}, fn step, {errs, missing} ->
        if module_exists?(index, step.module) do
          {errs, missing}
        else
          {[Error.missing_module(flow_id, step.module) | errs], MapSet.put(missing, step.module)}
        end
      end)

    {Enum.reverse(errors), missing_modules}
  end

  defp validate_functions(steps, index, flow_id, missing_modules) do
    {errors, missing_functions} =
      Enum.reduce(steps, {[], MapSet.new()}, fn step, {errs, missing} ->
        cond do
          MapSet.member?(missing_modules, step.module) ->
            {errs, missing}

          function_exists?(index.functions, step.module, step.function) ->
            {errs, missing}

          true ->
            error = Error.missing_function(flow_id, step.module, step.function)
            {[error | errs], MapSet.put(missing, {step.module, step.function})}
        end
      end)

    {Enum.reverse(errors), missing_functions}
  end

  defp module_exists?(index, module) when is_binary(module) do
    MapSet.member?(index.modules, module)
  end

  defp module_exists?(_index, _module), do: false

  defp function_exists?(functions, module, function)
       when is_binary(module) and is_binary(function) do
    function_arities(functions, module, function) != []
  end

  defp function_exists?(_functions, _module, _function), do: false

  defp function_arities(functions, module, function) do
    functions
    |> Map.get(module, MapSet.new())
    |> Enum.reduce([], fn {name, arity}, acc ->
      if name == function, do: [arity | acc], else: acc
    end)
    |> Enum.sort()
  end

  defp normalize_step(%PathStep{module: module, function: function}) do
    %{
      module: normalize_module(module),
      function: function
    }
  end

  defp normalize_step(%{module: module, function: function}) do
    %{
      module: normalize_module(module),
      function: function
    }
  end

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
