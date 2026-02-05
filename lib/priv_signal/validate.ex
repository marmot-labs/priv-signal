defmodule PrivSignal.Validate do
  @moduledoc false

  alias PrivSignal.Config.PathStep
  alias PrivSignal.Validate.{Error, Index, Result}
  require Logger

  @doc """
  Validates all configured flows against a single source index so scoring can fail fast
  when declared call chains drift from code.
  """
  def run(config, opts \\ []) do
    index_opts = Keyword.get(opts, :index, [])
    flows = config.flows || []
    flow_count = length(flows)
    # Build one index per run to keep validation deterministic and fast.
    start = System.monotonic_time()

    Logger.debug("[priv_signal] validate run starting flow_count=#{flow_count}")

    result =
      with {:ok, index} <- Index.build(index_opts) do
        results = Enum.map(flows, &validate_flow(&1, index))
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

    {function_errors, missing_functions} =
      validate_functions(steps, index, flow_id, missing_modules)

    edge_errors = validate_edges(steps, index, flow_id, missing_modules, missing_functions)

    errors = module_errors ++ function_errors ++ edge_errors
    status = if errors == [], do: :ok, else: :error

    %Result{flow_id: flow_id, status: status, errors: errors}
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

  defp validate_edges(steps, index, flow_id, missing_modules, missing_functions) do
    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce([], fn [from, to], errors ->
      if valid_step?(from, missing_modules, missing_functions) and
           valid_step?(to, missing_modules, missing_functions) do
        case edge_status(from, to, index) do
          :ok ->
            errors

          {:ambiguous, arity, entry} ->
            candidates = MapSet.to_list(entry.candidates) |> Enum.sort()

            error =
              Error.ambiguous_call(
                flow_id,
                from.module,
                from.function,
                entry.function,
                arity,
                candidates
              )

            [error | errors]

          :missing ->
            error =
              Error.missing_edge(flow_id, from.module, from.function, to.module, to.function)

            [error | errors]
        end
      else
        errors
      end
    end)
    |> Enum.reverse()
  end

  defp edge_status(from, to, index) do
    caller_arities = function_arities(index.functions, from.module, from.function)

    if edge_exists?(index.calls, caller_arities, from, to) do
      :ok
    else
      case ambiguous_entry(index.ambiguous_calls, caller_arities, from, to) do
        nil -> :missing
        {arity, entry} -> {:ambiguous, arity, entry}
      end
    end
  end

  defp edge_exists?(calls, caller_arities, from, to) do
    Enum.any?(caller_arities, fn arity ->
      case Map.get(calls, {from.module, from.function, arity}) do
        nil ->
          false

        callees ->
          Enum.any?(callees, fn {module_name, fun_name, _} ->
            module_name == to.module and fun_name == to.function
          end)
      end
    end)
  end

  defp ambiguous_entry(ambiguous_calls, caller_arities, from, to) do
    Enum.find_value(caller_arities, fn arity ->
      case Map.get(ambiguous_calls, {from.module, from.function, arity}) do
        nil ->
          nil

        entries ->
          match =
            Enum.find(entries, fn entry ->
              entry.function == to.function and MapSet.member?(entry.candidates, to.module)
            end)

          if match, do: {arity, match}, else: nil
      end
    end)
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

  defp valid_step?(step, missing_modules, missing_functions) do
    not MapSet.member?(missing_modules, step.module) and
      not MapSet.member?(missing_functions, {step.module, step.function})
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

    if stats.ambiguous_count > 0 do
      Logger.warning("[priv_signal] validate run ambiguous_calls=#{stats.ambiguous_count}")
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

    type_counts =
      Enum.frequencies_by(errors, fn
        %{type: type} when not is_nil(type) -> type
        _ -> :unknown
      end)

    %{
      status: status(results),
      error_count: length(errors),
      ambiguous_count: Map.get(type_counts, :ambiguous_call, 0)
    }
  end

  defp duration_ms(start) do
    # Standardize duration reporting for telemetry consumers.
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end
end
