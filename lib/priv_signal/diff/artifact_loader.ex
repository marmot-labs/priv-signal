defmodule PrivSignal.Diff.ArtifactLoader do
  @moduledoc false

  alias PrivSignal.Diff.Contract

  @type options :: %{
          required(:base) => String.t(),
          optional(:candidate_ref) => String.t() | nil,
          optional(:candidate_path) => String.t() | nil,
          optional(:artifact_path) => String.t() | nil,
          optional(:strict?) => boolean()
        }

  def load(options, opts \\ []) when is_map(options) do
    git_runner = Keyword.get(opts, :git_runner, &System.cmd/3)
    file_reader = Keyword.get(opts, :file_reader, &File.read/1)
    validator = Keyword.get(opts, :validator, &Contract.validate/2)
    strict? = Map.get(options, :strict?, false)

    with {:ok, base_raw} <- load_base(options, git_runner),
         {:ok, candidate_raw} <- load_candidate(options, git_runner, file_reader),
         {:ok, base} <- decode_and_validate(base_raw, :base, strict?, validator),
         {:ok, candidate} <- decode_and_validate(candidate_raw, :candidate, strict?, validator) do
      {:ok,
       %{
         base: base.artifact,
         candidate: candidate.artifact,
         warnings: base.warnings ++ candidate.warnings,
         metadata: %{
           base_ref: Map.fetch!(options, :base),
           candidate_source: candidate_source(options),
           schema_version_base: base.schema_version,
           schema_version_candidate: candidate.schema_version
         }
       }}
    end
  end

  defp load_base(options, git_runner) do
    base_ref = Map.fetch!(options, :base)
    artifact_path = artifact_path(options)
    source = "#{base_ref}:#{artifact_path}"

    with {:ok, output} <- git_show(git_runner, source) do
      {:ok, output}
    else
      {:error, {:artifact_not_found, details}} ->
        {:error, {:base_artifact_not_found, Map.put(details, :base_ref, base_ref)}}

      {:error, {:git_show_failed, details}} ->
        {:error, {:base_git_show_failed, Map.put(details, :base_ref, base_ref)}}
    end
  end

  defp load_candidate(options, git_runner, file_reader) do
    case Map.get(options, :candidate_ref) do
      candidate_ref when is_binary(candidate_ref) and candidate_ref != "" ->
        artifact_path = artifact_path(options)
        source = "#{candidate_ref}:#{artifact_path}"

        with {:ok, output} <- git_show(git_runner, source) do
          {:ok, output}
        else
          {:error, {:artifact_not_found, details}} ->
            {:error,
             {:candidate_artifact_not_found, Map.put(details, :candidate_ref, candidate_ref)}}

          {:error, {:git_show_failed, details}} ->
            {:error,
             {:candidate_git_show_failed, Map.put(details, :candidate_ref, candidate_ref)}}
        end

      _ ->
        candidate_path = candidate_path(options)

        case file_reader.(candidate_path) do
          {:ok, content} ->
            {:ok, content}

          {:error, :enoent} ->
            {:error, {:candidate_artifact_not_found, %{path: candidate_path, source: :workspace}}}

          {:error, reason} ->
            {:error,
             {:candidate_artifact_read_failed,
              %{path: candidate_path, source: :workspace, reason: inspect(reason)}}}
        end
    end
  end

  defp decode_and_validate(raw, side, strict?, validator) do
    with {:ok, decoded} <- decode_json(raw, side),
         {:ok, validated} <- validate_contract(decoded, side, strict?, validator) do
      {:ok, validated}
    end
  end

  defp validate_contract(decoded, side, strict?, validator) do
    case validator.(decoded, strict: strict?) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, reason} ->
        {:error, {contract_failure_type(side), %{reason: reason}}}
    end
  end

  defp decode_json(raw, side) do
    case Jason.decode(raw) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, error} ->
        {:error, {parse_failure_type(side), %{reason: Exception.message(error)}}}
    end
  end

  defp parse_failure_type(:base), do: :base_artifact_parse_failed
  defp parse_failure_type(:candidate), do: :candidate_artifact_parse_failed
  defp contract_failure_type(:base), do: :base_artifact_contract_failed
  defp contract_failure_type(:candidate), do: :candidate_artifact_contract_failed

  defp git_show(runner, source) do
    {output, status} = runner.("git", ["show", source], stderr_to_stdout: true)
    trimmed = String.trim(output)

    case status do
      0 ->
        {:ok, output}

      _ ->
        if artifact_not_found_message?(trimmed) do
          {:error, {:artifact_not_found, %{source: source, message: trimmed, status: status}}}
        else
          {:error, {:git_show_failed, %{source: source, message: trimmed, status: status}}}
        end
    end
  end

  defp artifact_not_found_message?(message) do
    String.contains?(message, "does not exist in") or
      String.contains?(message, "exists on disk, but not in") or
      String.contains?(message, "Path '")
  end

  defp artifact_path(options) do
    Map.get(options, :artifact_path) || "priv_signal.lockfile.json"
  end

  defp candidate_path(options) do
    Map.get(options, :candidate_path) || artifact_path(options)
  end

  defp candidate_source(options) do
    case Map.get(options, :candidate_ref) do
      candidate_ref when is_binary(candidate_ref) and candidate_ref != "" ->
        %{type: :git_ref, ref: candidate_ref, artifact_path: artifact_path(options)}

      _ ->
        %{type: :workspace, path: candidate_path(options)}
    end
  end
end
