defmodule PrivSignal.Diff.Normalize do
  @moduledoc """
  Normalizes lockfile artifacts so semantic comparisons ignore ordering noise.
  """

  alias PrivSignal.Infer.FlowIdentity
  alias PrivSignal.Infer.NodeNormalizer

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

    nodes =
      artifact
      |> get(:nodes, [])
      |> Enum.map(&normalize_node/1)
      |> Enum.sort_by(&node_sort_key/1)

    nodes_by_id = Map.new(nodes, &{&1.id, &1})

    flows =
      artifact
      |> get(:flows, [])
      |> Enum.map(&normalize_flow(&1, data_nodes_by_reference, nodes_by_id))
      |> Enum.sort_by(&flow_sort_key/1)

    %{
      schema_version: schema_version,
      data_nodes: data_nodes,
      data_nodes_by_key: data_nodes_by_key,
      data_node_keys: data_node_keys,
      nodes: nodes,
      nodes_by_id: nodes_by_id,
      flows: flows,
      flows_by_id: Map.new(flows, &{&1.id, &1}),
      flow_ids: MapSet.new(Enum.map(flows, & &1.id))
    }
  end

  defp normalize_flow(flow, data_nodes_by_reference, nodes_by_id) do
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

    normalized = %{
      id: normalize_string(get(flow, :id)),
      stable_id: normalize_string(get(flow, :stable_id)),
      variant_id: normalize_string(get(flow, :variant_id)),
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
      evidence: normalize_evidence(get(flow, :evidence, [])),
      location:
        normalize_location(get(flow, :location)) ||
          flow_location(get(flow, :evidence, []), nodes_by_id)
    }

    stable_id =
      if normalized.stable_id in [nil, ""] do
        FlowIdentity.id(normalized)
      else
        normalized.stable_id
      end

    variant_id =
      cond do
        normalized.variant_id not in [nil, ""] -> normalized.variant_id
        normalized.id not in [nil, ""] -> normalized.id
        true -> FlowIdentity.variant_id(normalized)
      end

    normalized
    |> Map.put(:stable_id, stable_id)
    |> Map.put(:variant_id, variant_id)
    |> Map.put(:id, variant_id)
  end

  defp flow_sort_key(flow) do
    {
      flow.stable_id,
      flow.id,
      flow.source,
      flow.source_class,
      flow.entrypoint,
      flow.sink.kind,
      flow.sink.subtype,
      flow.boundary,
      flow.confidence,
      flow.evidence,
      stable_location_key(flow.location)
    }
  end

  defp normalize_node(node) when is_map(node) do
    context = get(node, :code_context, %{})

    %{
      id: normalize_string(get(node, :id)),
      node_type: normalize_string(get(node, :node_type)),
      role_kind: normalize_string(get(get(node, :role, %{}), :kind)),
      code_context: %{
        module: normalize_string(get(context, :module)),
        function: normalize_string(get(context, :function)),
        file_path: normalize_path(get(context, :file_path)),
        lines: normalize_lines(get(context, :lines))
      },
      evidence: normalize_node_evidence(get(node, :evidence, []))
    }
  end

  defp normalize_node(_),
    do: %{id: "", node_type: "", role_kind: "", code_context: %{}, evidence: []}

  defp node_sort_key(node) do
    context = Map.get(node, :code_context, %{})

    {
      node.id,
      node.node_type,
      Map.get(context, :file_path, ""),
      Map.get(context, :function, ""),
      Map.get(context, :lines, []),
      node.role_kind
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

  defp normalize_node_evidence(values) when is_list(values) do
    values
    |> Enum.map(fn evidence ->
      %{
        line: normalize_integer(get(evidence, :line))
      }
    end)
    |> Enum.uniq()
    |> Enum.sort_by(&(&1.line || 0))
  end

  defp normalize_node_evidence(_), do: []

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

  defp normalize_location(location) when is_map(location) do
    case normalize_path(get(location, :file_path)) do
      "" ->
        nil

      file_path ->
        %{
          file_path: file_path,
          line: normalize_integer(get(location, :line))
        }
    end
  end

  defp normalize_location(_), do: nil

  defp flow_location(evidence_ids, nodes_by_id) when is_map(nodes_by_id) do
    evidence_ids
    |> normalize_evidence()
    |> Enum.map(&Map.get(nodes_by_id, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&present_string?(get_in(&1, [:code_context, :file_path])))
    |> Enum.sort_by(&node_location_rank/1)
    |> List.first()
    |> case do
      nil ->
        nil

      node ->
        %{
          file_path: get_in(node, [:code_context, :file_path]),
          line: best_node_line(node)
        }
    end
  end

  defp flow_location(_evidence_ids, _nodes_by_id), do: nil

  defp node_location_rank(node) do
    {
      node_type_rank(Map.get(node, :node_type)),
      line_rank(best_node_line(node)),
      get_in(node, [:code_context, :file_path]) || "",
      Map.get(node, :id) || ""
    }
  end

  defp node_type_rank("sink"), do: 0
  defp node_type_rank("source"), do: 1
  defp node_type_rank("entrypoint"), do: 2
  defp node_type_rank(_), do: 3

  defp line_rank(line) when is_integer(line), do: line
  defp line_rank(_line), do: 999_999_999

  defp best_node_line(node) do
    context_lines = get_in(node, [:code_context, :lines]) || []
    evidence_lines = Enum.map(Map.get(node, :evidence, []), & &1.line) |> Enum.reject(&is_nil/1)

    case Enum.sort(context_lines ++ evidence_lines) do
      [line | _] -> line
      [] -> nil
    end
  end

  defp stable_location_key(nil), do: {"", nil}
  defp stable_location_key(location), do: {location.file_path || "", location.line}

  defp normalize_boundary(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_boundary()

  defp normalize_boundary(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_boundary(_), do: "internal"

  defp normalize_string(nil), do: ""
  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(value) when is_atom(value), do: value |> Atom.to_string() |> String.trim()
  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)

  defp normalize_string(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 4)

  defp normalize_string(_), do: ""

  defp normalize_path(nil), do: ""

  defp normalize_path(path) do
    path
    |> NodeNormalizer.canonical_file_path()
    |> normalize_string()
  end

  defp normalize_lines(values) when is_list(values) do
    values
    |> Enum.map(&normalize_integer/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_lines(_), do: []

  defp normalize_integer(value) when is_integer(value), do: value
  defp normalize_integer(_), do: nil

  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_), do: false

  defp reference("", field), do: field
  defp reference(module_name, ""), do: module_name
  defp reference(module_name, field), do: "#{module_name}.#{field}"

  defp get(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default
  end
end
