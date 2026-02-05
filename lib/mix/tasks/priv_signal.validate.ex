defmodule Mix.Tasks.PrivSignal.Validate do
  use Mix.Task

  @shortdoc "Validate priv-signal.yml flows against source"

  @moduledoc """
  Validates configured data flows in priv-signal.yml against the project source.
  """

  @doc """
  Runs validation so CI can fail fast before scoring when flow definitions drift.
  """
  @impl true
  def run(_args) do
    # Ensure telemetry/config dependencies are started before reading config or indexing source.
    _ = PrivSignal.Runtime.ensure_started()

    with {:ok, config} <- load_config(),
         {:ok, results} <- PrivSignal.Validate.run(config) do
      # Emit structured output first so users see per-flow status before any failure.
      render_results(results)

      case PrivSignal.Validate.status(results) do
        :ok -> :ok
        :error -> Mix.raise("data flow validation failed")
      end
    else
      {:error, errors} ->
        render_errors(errors)
        Mix.raise("data flow validation failed")
    end
  end

  defp render_results(results) do
    results
    |> PrivSignal.Validate.Output.format_results()
    |> Enum.each(&emit_line/1)
  end

  defp render_errors(errors) do
    errors
    |> PrivSignal.Validate.Output.format_errors()
    |> Enum.each(&emit_line/1)
  end

  defp emit_line(%{level: :info, message: message}), do: Mix.shell().info(message)
  defp emit_line(%{level: :error, message: message}), do: Mix.shell().error(message)

  defp load_config do
    case PrivSignal.Config.Loader.load() do
      {:ok, config} ->
        Mix.shell().info("priv-signal.yml is valid")
        {:ok, config}

      {:error, errors} ->
        Mix.shell().error("priv-signal.yml is invalid")
        render_errors(errors)
        {:error, errors}
    end
  end
end
