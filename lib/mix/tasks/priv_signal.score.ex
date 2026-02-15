defmodule Mix.Tasks.PrivSignal.Score do
  use Mix.Task

  require Logger

  alias PrivSignal.Score

  @shortdoc "Compute deterministic privacy risk score from semantic diff JSON"

  @switches [help: :boolean, diff: :string, output: :string, quiet: :boolean]

  @impl true
  def run(args) do
    _ = PrivSignal.Runtime.ensure_started()

    case parse_args(args) do
      {:ok, options} ->
        PrivSignal.Telemetry.emit([:priv_signal, :score, :run, :start], %{}, %{})

        with {:ok, config} <- load_config(),
             {:ok, diff} <- Score.Input.load_diff_json(options.diff),
             {:ok, report} <- Score.Engine.run(diff, config.scoring),
             {:ok, llm_interpretation} <- run_advisory(diff, report, config, options),
             json <- Score.Output.JSON.render(report, llm_interpretation),
             {:ok, output_path} <- Score.Output.Writer.write(json, output: options.output) do
          unless options.quiet do
            Mix.shell().info("score=#{report.score} points=#{report.points}")
            Mix.shell().info("score output written: #{output_path}")
          end
        else
          {:error, reason} ->
            Logger.error("[priv_signal] score failed reason=#{inspect(reason)}")
            Mix.shell().error(format_error(reason))

            PrivSignal.Telemetry.emit(
              [:priv_signal, :score, :run, :error],
              %{error_count: 1},
              %{reason: inspect(reason)}
            )

            Mix.raise("score failed")
        end

      :help ->
        :ok

      {:error, reason} ->
        Mix.shell().error(format_error(reason))
        Mix.raise("score failed")
    end
  end

  defp parse_args(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    cond do
      invalid != [] ->
        {:error,
         "invalid options: #{Enum.map_join(invalid, ", ", fn {opt, _} -> "--#{opt}" end)}"}

      Keyword.get(opts, :help, false) ->
        Mix.shell().info(usage())
        :help

      not is_binary(Keyword.get(opts, :diff)) ->
        {:error, "--diff is required"}

      true ->
        {:ok,
         %{
           diff: Keyword.fetch!(opts, :diff),
           output: Keyword.get(opts, :output, "priv_signal_score.json"),
           quiet: Keyword.get(opts, :quiet, false)
         }}
    end
  end

  defp load_config do
    case PrivSignal.Config.Loader.load(PrivSignal.config_path(), mode: :score) do
      {:ok, config} -> {:ok, config}
      {:error, reason} -> {:error, {:config_load_failed, reason}}
    end
  end

  defp run_advisory(diff, report, config, options) do
    case Score.Advisory.run(diff, report, config.scoring.llm_interpretation) do
      {:ok, payload} ->
        {:ok, payload}

      {:error, reason} ->
        unless options.quiet do
          Mix.shell().error("advisory interpretation failed (non-fatal): #{inspect(reason)}")
        end

        {:ok, %{error: inspect(reason)}}
    end
  end

  defp format_error({:config_load_failed, reason}), do: "config load failed: #{inspect(reason)}"
  defp format_error({:diff_json_parse_failed, reason}), do: "diff JSON parse failed: #{reason}"

  defp format_error(
         {:unsupported_diff_version, %{version: version, supported_versions: supported}}
       ) do
    "unsupported diff version #{version}; supported versions: #{Enum.join(supported, ", ")}"
  end

  defp format_error({:missing_required_field, field}), do: "missing required field: #{field}"

  defp format_error({:invalid_change, %{index: idx, reason: reason}}),
    do: "invalid change at index #{idx}: #{reason}"

  defp format_error({:invalid_diff_contract, reason}),
    do: "invalid diff contract: #{inspect(reason)}"

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp usage do
    """
    Usage:
      mix priv_signal.score --diff <path> [options]

    Options:
      --diff <path>       Path to semantic diff JSON artifact (required)
      --output <path>     Output score JSON path (default: priv_signal_score.json)
      --quiet             Suppress CLI summary output
      --help              Show this help
    """
  end
end
