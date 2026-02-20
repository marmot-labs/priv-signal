defmodule PrivSignal.Validate.Output do
  @moduledoc false

  alias PrivSignal.Validate.{Error, Result}

  @doc """
  Formats full validation results into structured log lines so Mix tasks can render
  a deterministic summary and per-scope status.
  """
  def format_results(results) when is_list(results) do
    # Keep the summary first so CI logs surface overall status immediately.
    status = if Enum.all?(results, &Result.ok?/1), do: :ok, else: :error
    summary_level = if status == :ok, do: :info, else: :error
    summary = %{level: summary_level, message: "config validation: #{format_status(status)}"}

    [summary | Enum.flat_map(results, &format_result/1)]
  end

  @doc """
  Formats validation errors into structured error lines for consistent CLI output.
  """
  def format_errors(errors) when is_list(errors) do
    # Treat all errors as error-level output to ensure failures are visible in CI.
    Enum.map(errors, fn error ->
      message =
        if is_binary(error) do
          error
        else
          Error.format(error)
        end

      %{level: :error, message: message}
    end)
  end

  defp format_result(%Result{flow_id: flow_id, status: status, errors: errors}) do
    header_level = if status == :ok, do: :info, else: :error
    header = %{level: header_level, message: "scope #{flow_id}: #{format_status(status)}"}

    error_lines =
      Enum.map(errors, fn error ->
        %{level: :error, message: "  - #{Error.format(error)}"}
      end)

    [header | error_lines]
  end

  defp format_status(:ok), do: "ok"
  defp format_status(:error), do: "error"
  defp format_status(other), do: to_string(other)
end
