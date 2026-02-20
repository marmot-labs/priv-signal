defmodule PrivSignal.Diff.Normalize do
  @moduledoc false

  def normalize(artifact) when is_map(artifact) do
    schema_version = get(artifact, :schema_version)

    data_nodes =
      artifact
      |> get(:data_nodes, [])
      |> Enum.map(&normalize_data_node/1)
      |> Enum.sort_by(&data_node_sort_key/1)

    data_nodes_by_key = Map.new(data_nodes, &{&1.key, &1})
    data_node_keys = MapSet.new(Enum.map(data_nodes, & &1.key))
    data_nodes_by_reference = Map.new(data_nodes, &{&1.reference, &1})

    flows =
      artifact
      |> get(:flows, [])
      |> Enum.map(&normalize_flow(&1, data_nodes_by_reference))
      |> Enum.sort_by(&flow_sort_key/1)

    %{
      schema_version: schema_version,
      data_nodes: data_nodes,
      data_nodes_by_key: data_nodes_by_key,
      data_node_keys: data_node_keys,
      flows: flows,
      flows_by_id: Map.new(flows, &{&1.id, &1}),
      flow_ids: MapSet.new(Enum.map(flows, & &1.id))
    }
  end

  defp normalize_flow(flow, data_nodes_by_reference) do
    sink = get(flow, :sink, %{})
    source = normalize_source(get(flow, :source))
    source_node = Map.get(data_nodes_by_reference, source)
    linked_refs = normalize_string_list(get(flow, :linked_refs, [source]))

    linked_classes =
      case normalize_string_list(get(flow, :linked_classes, [])) do
        [] ->
          linked_refs
          |> Enum.map(&Map.get(data_nodes_by_reference, &1))
          |> Enum.map(&(&1 && &1.class))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.sort()

        provided ->
          provided
      end

    %{
      id: normalize_string(get(flow, :id)),
      source: source,
      source_key: normalize_string(get(flow, :source_key) || (source_node && source_node.key)),
      source_class:
        normalize_string(get(flow, :source_class) || (source_node && source_node.class)),
      source_sensitive:
        normalize_boolean(get(flow, :source_sensitive), source_node && source_node.sensitive),
      linked_refs: linked_refs,
      linked_classes: linked_classes,
      entrypoint: normalize_string(get(flow, :entrypoint)),
      sink: %{
        kind: normalize_string(get(sink, :kind)),
        subtype: normalize_string(get(sink, :subtype))
      },
      boundary: normalize_boundary(get(flow, :boundary)),
      confidence: normalize_confidence(get(flow, :confidence)),
      evidence: normalize_evidence(get(flow, :evidence, []))
    }
  end

  defp flow_sort_key(flow) do
    {
      flow.id,
      flow.source,
      flow.source_class,
      flow.entrypoint,
      flow.sink.kind,
      flow.sink.subtype,
      flow.boundary,
      flow.confidence,
      flow.evidence
    }
  end

  defp normalize_source(source) when is_binary(source), do: String.trim(source)
  defp normalize_source(source), do: normalize_string(source)

  defp normalize_data_node(data_node) do
    scope = get(data_node, :scope, %{})
    module_name = normalize_string(get(scope, :module))
    field_name = normalize_string(get(scope, :field))
    reference = reference(module_name, field_name)

    %{
      key: normalize_string(get(data_node, :key)),
      name: normalize_string(get(data_node, :name)),
      class: normalize_string(get(data_node, :class)),
      sensitive: normalize_boolean(get(data_node, :sensitive), false),
      scope: %{module: module_name, field: field_name},
      reference: reference
    }
  end

  defp data_node_sort_key(data_node) do
    {data_node.key, data_node.class, data_node.reference, data_node.sensitive}
  end

  defp normalize_evidence(values) when is_list(values) do
    values
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_evidence(_), do: []

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_string_list(_), do: []

  defp normalize_boolean(value, _default) when value in [true, "true"], do: true
  defp normalize_boolean(value, _default) when value in [false, "false"], do: false
  defp normalize_boolean(_value, default), do: default

  defp normalize_confidence(value) when is_float(value), do: Float.round(value, 4)
  defp normalize_confidence(value) when is_integer(value), do: (value * 1.0) |> Float.round(4)

  defp normalize_confidence(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {parsed, ""} -> Float.round(parsed, 4)
      _ -> 0.0
    end
  end

  defp normalize_confidence(_), do: 0.0

  defp normalize_boundary(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_boundary()

  defp normalize_boundary(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_boundary(_), do: "internal"

  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(value) when is_atom(value), do: value |> Atom.to_string() |> String.trim()
  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)

  defp normalize_string(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 4)

  defp normalize_string(_), do: ""

  defp reference("", field), do: field
  defp reference(module_name, ""), do: module_name
  defp reference(module_name, field), do: "#{module_name}.#{field}"

  defp get(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default
  end
end
