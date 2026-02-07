defmodule Mix.Tasks.PrivSignal.Scan do
  use Mix.Task

  @shortdoc "Scan source for PII-relevant logging statements"

  @moduledoc """
  Runs the PII logging scanner and writes deterministic JSON output.

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
    json_path = Keyword.get(opts, :json_path, "priv-signal-scan.json")
    timeout_ms = Keyword.get(opts, :timeout_ms)
    max_concurrency = Keyword.get(opts, :max_concurrency)

    with {:ok, config} <- load_config(),
         run_result <-
           PrivSignal.Scan.Runner.run(config,
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
          Mix.raise("scan failed in strict mode")
      end
    else
      {:error, errors} ->
        render_errors(errors)
        Mix.raise("scan failed")
    end
  end

  defp emit_outputs(result, quiet?, json_path) do
    markdown = PrivSignal.Scan.Output.Markdown.render(result)
    json = PrivSignal.Scan.Output.JSON.render(result)

    case PrivSignal.Scan.Output.Writer.write(markdown, json, quiet: quiet?, json_path: json_path) do
      {:ok, _path} ->
        :ok

      {:error, reason} ->
        Mix.raise("failed to write scan output: #{inspect(reason)}")
    end
  end

  defp emit_summary(result, json_path) do
    summary = result.summary

    Mix.shell().info(
      "scan findings: confirmed=#{summary.confirmed_count} possible=#{summary.possible_count}"
    )

    Mix.shell().info("scan errors: #{summary.errors}")
    Mix.shell().info("scan json written: #{json_path}")
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
