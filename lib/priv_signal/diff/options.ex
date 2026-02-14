defmodule PrivSignal.Diff.Options do
  @moduledoc false

  @default_artifact_path "priv_signal.lockfile.json"
  @default_format :human

  @switches [
    help: :boolean,
    base: :string,
    candidate_ref: :string,
    candidate_path: :string,
    artifact_path: :string,
    format: :string,
    include_confidence: :boolean,
    strict: :boolean,
    output: :string
  ]

  @aliases [b: :base]

  def parse(args) when is_list(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches, aliases: @aliases)
    invalid_errors = Enum.map(invalid, &format_invalid_option/1)

    case Keyword.get(opts, :help, false) do
      true ->
        {:ok, %{help?: true}}

      false ->
        with :ok <- validate_invalid_options(invalid_errors),
             {:ok, base} <- validate_base(opts),
             :ok <- validate_candidate_source(opts),
             {:ok, format} <- validate_format(opts) do
          artifact_path = Keyword.get(opts, :artifact_path, @default_artifact_path)
          candidate_ref = Keyword.get(opts, :candidate_ref)
          candidate_path = candidate_path(opts, artifact_path, candidate_ref)

          {:ok,
           %{
             help?: false,
             base: base,
             candidate_ref: candidate_ref,
             candidate_path: candidate_path,
             artifact_path: artifact_path,
             format: format,
             include_confidence?: Keyword.get(opts, :include_confidence, false),
             strict?: Keyword.get(opts, :strict, false),
             output: Keyword.get(opts, :output)
           }}
        end
    end
  end

  def default_artifact_path, do: @default_artifact_path

  defp validate_invalid_options([]), do: :ok
  defp validate_invalid_options(errors), do: {:error, errors}

  defp validate_base(opts) do
    case Keyword.get(opts, :base) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, ["--base is required"]}
    end
  end

  defp validate_candidate_source(opts) do
    case {Keyword.get(opts, :candidate_ref), Keyword.get(opts, :candidate_path)} do
      {candidate_ref, candidate_path}
      when is_binary(candidate_ref) and candidate_ref != "" and is_binary(candidate_path) and
             candidate_path != "" ->
        {:error, ["--candidate-ref and --candidate-path are mutually exclusive"]}

      _ ->
        :ok
    end
  end

  defp validate_format(opts) do
    case Keyword.get(opts, :format, Atom.to_string(@default_format)) do
      "human" -> {:ok, :human}
      "json" -> {:ok, :json}
      value -> {:error, ["--format must be one of: human, json (got: #{value})"]}
    end
  end

  defp candidate_path(opts, _artifact_path, candidate_ref) when is_binary(candidate_ref) do
    Keyword.get(opts, :candidate_path)
  end

  defp candidate_path(opts, artifact_path, nil) do
    Keyword.get(opts, :candidate_path, artifact_path)
  end

  defp format_invalid_option({option, nil}) do
    "invalid option: --#{option}"
  end

  defp format_invalid_option({option, value}) do
    "invalid option: --#{option}=#{value}"
  end
end
