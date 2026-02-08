defmodule Mix.Tasks.PrivSignal.Diff do
  use Mix.Task

  require Logger

  alias PrivSignal.Diff.Options
  alias PrivSignal.Diff.Runner

  @shortdoc "Compare privacy lockfile artifacts semantically"

  @moduledoc """
  Compares semantic privacy changes between lockfile artifacts.

  Phase 1 provides CLI contract parsing and validation only.

  Options:
  - `--base REF` (required)
  - `--candidate-ref REF` (optional; mutually exclusive with `--candidate-path`)
  - `--candidate-path PATH` (optional; defaults to `priv-signal-infer.json`)
  - `--artifact-path PATH` (optional; default lockfile path)
  - `--format human|json` (optional; default `human`)
  - `--include-confidence` (optional)
  - `--strict` (optional)
  - `--output PATH` (optional)
  - `--help`
  """

  @impl true
  def run(args) do
    _ = PrivSignal.Runtime.ensure_started()

    with {:ok, parsed} <- Options.parse(args) do
      case parsed.help? do
        true ->
          Mix.shell().info(usage())
          :ok

        false ->
          run_diff(parsed)
      end
    else
      {:error, errors} when is_list(errors) ->
        Enum.each(errors, &Mix.shell().error/1)
        Mix.shell().info(usage())
        Mix.raise("diff failed")

      {:error, reason} ->
        Mix.shell().error(inspect(reason))
        Mix.shell().info(usage())
        Mix.raise("diff failed")
    end
  end

  defp run_diff(parsed) do
    case Runner.run(parsed) do
      {:ok, result} ->
        emit_warnings(result.report.warnings)
        output = build_output(result, parsed.format)
        emit_output(output, parsed.output)
        :ok

      {:error, reason} ->
        Mix.shell().error(format_error(reason))
        Mix.raise("diff failed")
    end
  end

  defp build_output(result, :human), do: result.human
  defp build_output(result, :json), do: Jason.encode!(result.json, pretty: true)

  defp emit_output(output, nil) do
    Mix.shell().info(output)
  end

  defp emit_output(output, path) when is_binary(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, output)
    Mix.shell().info("diff output written: #{path}")
  end

  defp emit_warnings(warnings) when is_list(warnings) do
    Enum.each(warnings, fn warning ->
      Logger.warning("[priv_signal] #{warning}")
    end)
  end

  defp format_error({:base_artifact_not_found, %{base_ref: base_ref, source: source}}) do
    "base artifact not found for ref #{base_ref} (#{source}); ensure lockfile exists in base branch"
  end

  defp format_error({:candidate_artifact_not_found, %{source: :workspace, path: path}}) do
    "candidate workspace artifact not found at #{path}; run mix priv_signal.infer --write-lock and commit"
  end

  defp format_error(
         {:candidate_artifact_not_found, %{candidate_ref: candidate_ref, source: source}}
       ) do
    "candidate artifact not found for ref #{candidate_ref} (#{source})"
  end

  defp format_error({:base_git_show_failed, %{base_ref: base_ref, message: message}}) do
    "failed reading base ref #{base_ref}: #{message}"
  end

  defp format_error(
         {:candidate_git_show_failed, %{candidate_ref: candidate_ref, message: message}}
       ) do
    "failed reading candidate ref #{candidate_ref}: #{message}"
  end

  defp format_error({:base_artifact_parse_failed, %{reason: reason}}),
    do: "base artifact JSON parse failed: #{reason}"

  defp format_error({:candidate_artifact_parse_failed, %{reason: reason}}),
    do: "candidate artifact JSON parse failed: #{reason}"

  defp format_error({:base_artifact_contract_failed, %{reason: reason}}),
    do: "base artifact contract validation failed: #{inspect(reason)}"

  defp format_error({:candidate_artifact_contract_failed, %{reason: reason}}),
    do: "candidate artifact contract validation failed: #{inspect(reason)}"

  defp format_error(reason), do: inspect(reason)

  defp usage do
    """
    Usage:
      mix priv_signal.diff --base <ref> [options]

    Options:
      --base <ref>                 Base git ref (required)
      --candidate-ref <ref>        Candidate git ref (optional)
      --candidate-path <path>      Candidate workspace lockfile path (optional)
      --artifact-path <path>       Default lockfile path for both sources (optional)
      --format <human|json>        Output format (default: human)
      --include-confidence         Include confidence change comparisons
      --strict                     Treat optional artifact gaps as errors
      --output <path>              Write output to file
      --help                       Show this help
    """
  end
end
