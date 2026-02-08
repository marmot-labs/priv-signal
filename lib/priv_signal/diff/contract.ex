defmodule PrivSignal.Diff.Contract do
  @moduledoc false

  @supported_schema_versions MapSet.new(["1.1", "1.2"])
  @required_artifact_keys [:schema_version, :flows]
  @required_flow_keys [:id, :source, :entrypoint, :sink, :boundary]
  @optional_artifact_keys [:nodes]
  @optional_flow_keys [:confidence, :evidence]

  def supported_schema_versions, do: MapSet.to_list(@supported_schema_versions)

  def validate(artifact, opts \\ []) do
    strict? = Keyword.get(opts, :strict, false)

    with :ok <- validate_artifact_map(artifact),
         {:ok, schema_version} <- validate_schema_version(artifact),
         :ok <- validate_required_keys(artifact, @required_artifact_keys, :artifact),
         {:ok, flows} <- validate_flows(artifact),
         :ok <- validate_flows_required(flows) do
      optional_paths = missing_optional_paths(artifact, flows)

      case {strict?, optional_paths} do
        {true, [_ | _]} ->
          {:error, {:missing_optional_sections, %{paths: optional_paths}}}

        _ ->
          {:ok,
           %{
             artifact: artifact,
             schema_version: schema_version,
             warnings: optional_warnings(optional_paths)
           }}
      end
    end
  end

  defp validate_artifact_map(artifact) when is_map(artifact), do: :ok

  defp validate_artifact_map(_),
    do: {:error, {:invalid_artifact_shape, %{reason: "artifact must be a map"}}}

  defp validate_schema_version(artifact) do
    case get(artifact, :schema_version) do
      version when is_binary(version) ->
        if MapSet.member?(@supported_schema_versions, version) do
          {:ok, version}
        else
          {:error,
           {:unsupported_schema_version,
            %{schema_version: version, supported: supported_schema_versions()}}}
        end

      _ ->
        {:error, {:missing_required_keys, %{scope: :artifact, keys: ["schema_version"]}}}
    end
  end

  defp validate_required_keys(map, keys, scope) do
    missing =
      keys
      |> Enum.reject(&has_key?(map, &1))
      |> Enum.map(&Atom.to_string/1)

    case missing do
      [] -> :ok
      _ -> {:error, {:missing_required_keys, %{scope: scope, keys: missing}}}
    end
  end

  defp validate_flows(artifact) do
    case get(artifact, :flows) do
      flows when is_list(flows) -> {:ok, flows}
      _ -> {:error, {:invalid_artifact_shape, %{reason: "flows must be a list"}}}
    end
  end

  defp validate_flows_required(flows) do
    flows
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {flow, idx}, :ok ->
      with :ok <- validate_flow_map(flow, idx),
           :ok <- validate_required_keys(flow, @required_flow_keys, {:flow, idx}),
           :ok <- validate_flow_sink(flow, idx),
           :ok <- validate_flow_boundary(flow, idx) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_flow_map(flow, _idx) when is_map(flow), do: :ok

  defp validate_flow_map(_flow, idx) do
    {:error, {:invalid_flow_shape, %{index: idx, reason: "flow must be a map"}}}
  end

  defp validate_flow_sink(flow, idx) do
    sink = get(flow, :sink)

    cond do
      not is_map(sink) ->
        {:error, {:invalid_sink, %{index: idx, reason: "sink must be a map"}}}

      blank?(get(sink, :kind)) ->
        {:error, {:invalid_sink, %{index: idx, reason: "sink.kind must be a non-empty string"}}}

      blank?(get(sink, :subtype)) ->
        {:error,
         {:invalid_sink, %{index: idx, reason: "sink.subtype must be a non-empty string"}}}

      true ->
        :ok
    end
  end

  defp validate_flow_boundary(flow, idx) do
    boundary = get(flow, :boundary)

    case normalize_boundary(boundary) do
      value when value in ["internal", "external"] -> :ok
      _ -> {:error, {:invalid_boundary, %{index: idx, boundary: boundary}}}
    end
  end

  defp normalize_boundary(boundary) when is_atom(boundary),
    do: boundary |> Atom.to_string() |> normalize_boundary()

  defp normalize_boundary(boundary) when is_binary(boundary),
    do: boundary |> String.trim() |> String.downcase()

  defp normalize_boundary(_), do: nil

  defp missing_optional_paths(artifact, flows) do
    artifact_missing =
      @optional_artifact_keys
      |> Enum.reject(&has_key?(artifact, &1))
      |> Enum.map(&Atom.to_string/1)

    flow_missing =
      flows
      |> Enum.with_index()
      |> Enum.flat_map(fn {flow, idx} ->
        @optional_flow_keys
        |> Enum.reject(&has_key?(flow, &1))
        |> Enum.map(fn key -> "flows[#{idx}].#{key}" end)
      end)

    artifact_missing ++ flow_missing
  end

  defp optional_warnings([]), do: []

  defp optional_warnings(paths) do
    Enum.map(paths, fn path -> "optional section missing: #{path}" end)
  end

  defp get(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp has_key?(map, key) do
    Map.has_key?(map, key) or Map.has_key?(map, Atom.to_string(key))
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: true
end
