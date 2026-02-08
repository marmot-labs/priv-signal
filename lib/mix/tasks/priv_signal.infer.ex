defmodule Mix.Tasks.PrivSignal.Infer do
  use Mix.Task

  @shortdoc "Generate deterministic PII node inventory"

  @moduledoc """
  Runs infer inventory generation and writes deterministic JSON output.

  Options:
  - `--strict`
  - `--json-path PATH`
  - `--quiet`
  - `--timeout-ms N`
  - `--max-concurrency N`
  """

  @switches [
    strict: :boolean,
    quiet: :boolean,
    json_path: :string,
    timeout_ms: :integer,
    max_concurrency: :integer
  ]

  @impl true
  def run(args) do
    _ = PrivSignal.Runtime.ensure_started()

    {opts, _argv, _invalid} = OptionParser.parse(args, strict: @switches)
    strict? = Keyword.get(opts, :strict, false)
    quiet? = Keyword.get(opts, :quiet, false)
    json_path = Keyword.get(opts, :json_path, "priv-signal-infer.json")
    timeout_ms = Keyword.get(opts, :timeout_ms)
    max_concurrency = Keyword.get(opts, :max_concurrency)

    with {:ok, config} <- load_config(),
         run_result <-
           PrivSignal.Infer.Runner.run(config,
             strict: strict?,
             timeout: timeout_ms,
             max_concurrency: max_concurrency
           ) do
      case run_result do
        {:ok, result} ->
          emit_outputs(result, quiet?, json_path)
          emit_summary(result, json_path)
          :ok

        {:error, {:strict_mode_failed, result}} ->
          emit_outputs(result, quiet?, json_path)
          emit_summary(result, json_path)
          Mix.raise("infer failed in strict mode")
      end
    else
      {:error, errors} ->
        render_errors(errors)
        Mix.raise("infer failed")
    end
  end

  defp emit_outputs(result, quiet?, json_path) do
    markdown = PrivSignal.Infer.Output.Markdown.render(result)
    json = PrivSignal.Infer.Output.JSON.render(result)

    case PrivSignal.Infer.Output.Writer.write(markdown, json, quiet: quiet?, json_path: json_path) do
      {:ok, _path} ->
        :ok

      {:error, reason} ->
        Mix.raise("failed to write infer output: #{inspect(reason)}")
    end
  end

  defp emit_summary(result, json_path) do
    summary = Map.get(result, :summary, %{})

    Mix.shell().info("infer nodes: total=#{Map.get(summary, :node_count, 0)}")
    Mix.shell().info("infer flows: total=#{Map.get(summary, :flow_count, 0)}")
    Mix.shell().info("infer errors: #{Map.get(summary, :scan_error_count, 0)}")
    Mix.shell().info("infer json written: #{json_path}")
  end

  defp render_errors(errors) when is_list(errors) do
    Enum.each(errors, fn error ->
      Mix.shell().error("- #{format_error(error)}")
    end)
  end

  defp render_errors(error), do: Mix.shell().error("- #{format_error(error)}")

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)

  defp load_config do
    case PrivSignal.Config.Loader.load() do
      {:ok, config} ->
        Mix.shell().info("priv-signal.yml is valid")
        {:ok, config}

      {:error, errors} ->
        Mix.shell().error("priv-signal.yml is invalid")
        {:error, errors}
    end
  end
end
