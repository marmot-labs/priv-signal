defmodule PrivSignal.Infer.Contract do
  @moduledoc false

  alias PrivSignal.Infer.NodeNormalizer

  @schema_version "1.2"
  @supported_schema_versions MapSet.new(["1.0", "1.1", "1.2"])
  @node_types MapSet.new(["entrypoint", "source", "sink", "transform"])
  @boundaries MapSet.new(["internal", "external"])

  def schema_version, do: @schema_version
  def supported_schema_versions, do: MapSet.to_list(@supported_schema_versions)

  def compatible_schema_version?(schema_version) when is_binary(schema_version) do
    MapSet.member?(@supported_schema_versions, schema_version)
  end

  def compatible_schema_version?(_), do: false

  def required_artifact_keys(schema_version \\ @schema_version) do
    base = [:schema_version, :tool, :git, :summary, :nodes, :errors]

    if schema_version == "1.2" do
      [:schema_version, :tool, :git, :summary, :nodes, :flows, :errors]
    else
      base
    end
  end

  def required_node_keys do
    [:id, :node_type, :pii, :code_context, :role, :evidence, :confidence]
  end

  def valid_node_type?(node_type) do
    node_type
    |> normalize_node_type()
    |> then(&MapSet.member?(@node_types, &1))
  end

  def valid_node?(node) when is_map(node) do
    required_node_keys_present?(node) and valid_node_type?(get(node, :node_type))
  end

  def valid_node?(_), do: false

  def valid_artifact?(artifact) when is_map(artifact) do
    schema_version = get(artifact, :schema_version)
    required_keys = required_artifact_keys(schema_version)

    required_artifact_keys_present?(artifact, required_keys) and
      compatible_schema_version?(schema_version) and
      is_list(get(artifact, :nodes)) and
      valid_artifact_flows?(artifact, schema_version) and
      is_list(get(artifact, :errors))
  end

  def valid_artifact?(_), do: false

  def stable_sort_nodes(nodes) when is_list(nodes) do
    nodes
    |> Enum.map(&NodeNormalizer.normalize/1)
    |> Enum.sort_by(&NodeNormalizer.sort_key/1)
  end

  def required_flow_keys do
    [:id, :source, :entrypoint, :sink, :boundary, :confidence, :evidence]
  end

  def valid_flow?(flow) when is_map(flow) do
    required_flow_keys_present?(flow) and
      valid_boundary?(get(flow, :boundary)) and
      valid_sink?(get(flow, :sink)) and
      is_number(get(flow, :confidence)) and
      is_list(get(flow, :evidence))
  end

  def valid_flow?(_), do: false

  def stable_sort_flows(flows) when is_list(flows) do
    Enum.sort_by(flows, fn flow ->
      sink = get(flow, :sink) || %{}

      {
        get(flow, :id) || "",
        get(flow, :entrypoint) || "",
        get(flow, :source) || "",
        get(sink, :kind) || "",
        get(sink, :subtype) || "",
        get(flow, :boundary) || "",
        get(flow, :confidence) || 0.0,
        get(flow, :evidence) || []
      }
    end)
  end

  defp required_node_keys_present?(node) do
    Enum.all?(required_node_keys(), &has_key?(node, &1))
  end

  defp required_artifact_keys_present?(artifact, required_keys) do
    Enum.all?(required_keys, &has_key?(artifact, &1))
  end

  defp valid_artifact_flows?(artifact, "1.2"), do: is_list(get(artifact, :flows))
  defp valid_artifact_flows?(_artifact, _schema_version), do: true

  defp required_flow_keys_present?(flow) do
    Enum.all?(required_flow_keys(), &has_key?(flow, &1))
  end

  defp valid_boundary?(value) when is_atom(value),
    do: value |> Atom.to_string() |> valid_boundary?()

  defp valid_boundary?(value) when is_binary(value),
    do: MapSet.member?(@boundaries, String.trim(String.downcase(value)))

  defp valid_boundary?(_), do: false

  defp valid_sink?(sink) when is_map(sink) do
    kind = get(sink, :kind)
    subtype = get(sink, :subtype)

    is_binary(kind) and String.trim(kind) != "" and is_binary(subtype) and
      String.trim(subtype) != ""
  end

  defp valid_sink?(_), do: false

  defp get(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp normalize_node_type(node_type) when is_atom(node_type),
    do: node_type |> Atom.to_string() |> normalize_node_type()

  defp normalize_node_type(node_type) when is_binary(node_type) do
    node_type
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_node_type(_), do: ""

  defp has_key?(map, key) do
    Map.has_key?(map, key) or Map.has_key?(map, Atom.to_string(key))
  end
end
