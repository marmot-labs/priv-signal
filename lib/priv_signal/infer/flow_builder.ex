defmodule PrivSignal.Infer.FlowBuilder do
  @moduledoc false

  alias PrivSignal.Infer.{Contract, Flow, FlowIdentity, FlowScorer}

  @external_sink_kinds MapSet.new([
                         "http",
                         "http_response",
                         "http_client",
                         "external_http",
                         "liveview_render",
                         "telemetry",
                         "webhook",
                         "s3",
                         "smtp",
                         "email",
                         "third_party"
                       ])

  def build(nodes, opts \\ [])

  def build(nodes, opts) when is_list(nodes) do
    grouped =
      nodes
      |> Enum.reduce(%{}, fn node, acc ->
        case group_key(node) do
          nil -> acc
          key -> Map.update(acc, key, [node], &[node | &1])
        end
      end)

    flows =
      grouped
      |> Enum.flat_map(fn {key, group_nodes} -> flows_for_group(key, group_nodes, opts) end)
      |> dedupe_by_semantics()
      |> Contract.stable_sort_flows()

    %{
      flows: flows,
      candidate_count: length(flows)
    }
  end

  def build(_nodes, _opts), do: %{flows: [], candidate_count: 0}

  defp flows_for_group({_module_name, _function_name, _file_path} = key, nodes, opts) do
    sinks = Enum.filter(nodes, &(Map.get(&1, :node_type) == "sink"))
    references = source_refs(nodes)

    if sinks == [] or references == [] do
      []
    else
      entrypoint = entrypoint_for_group(key, nodes)
      linked_refs = references |> Enum.map(& &1.reference) |> Enum.uniq() |> Enum.sort()

      linked_classes =
        references |> Enum.map(& &1.class) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()

      sinks
      |> Enum.flat_map(fn sink ->
        Enum.map(references, fn reference ->
          flow_from_sink_reference(
            sink,
            reference,
            entrypoint,
            nodes,
            linked_refs,
            linked_classes,
            opts
          )
        end)
      end)
    end
  end

  defp flow_from_sink_reference(
         sink,
         reference,
         entrypoint,
         group_nodes,
         linked_refs,
         linked_classes,
         opts
       ) do
    sink_kind = sink |> role_value(:kind) |> normalize_kind()
    sink_subtype = sink |> role_value(:callee) |> normalize_subtype()
    evidence = evidence_for_reference(group_nodes, sink, reference.reference)
    boundary = boundary_for_kind(sink_kind)

    confidence =
      FlowScorer.score(
        %{
          same_function_context: true,
          direct_reference: direct_reference?(sink, reference.reference),
          possible_pii: possible_pii?(sink),
          indirect_only: not direct_reference?(sink, reference.reference)
        },
        opts
      )

    flow = %Flow{
      source: reference.reference,
      source_key: reference.key,
      source_class: reference.class,
      source_sensitive: reference.sensitive,
      linked_refs: linked_refs,
      linked_classes: linked_classes,
      entrypoint: entrypoint,
      sink: %{kind: sink_kind, subtype: sink_subtype},
      boundary: boundary,
      confidence: confidence,
      evidence: evidence
    }

    %{flow | id: FlowIdentity.id(flow)}
  end

  defp evidence_for_reference(group_nodes, sink, reference) do
    group_nodes
    |> Enum.filter(fn node ->
      node_id(node) == node_id(sink) or node_has_reference?(node, reference)
    end)
    |> Enum.map(&node_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp dedupe_by_semantics(flows) do
    flows
    |> Enum.group_by(fn flow ->
      sink = Map.get(flow, :sink, %{})

      {flow.source, flow.source_class, flow.entrypoint, Map.get(sink, :kind),
       Map.get(sink, :subtype), flow.boundary}
    end)
    |> Enum.map(fn {_key, candidates} ->
      candidates
      |> Enum.sort_by(fn flow ->
        {
          -(flow.confidence || 0.0),
          -length(flow.evidence || []),
          flow.id || ""
        }
      end)
      |> hd()
    end)
  end

  defp source_refs(nodes) do
    nodes
    |> Enum.flat_map(fn node ->
      node
      |> Map.get(:data_refs, Map.get(node, :pii, Map.get(node, "pii", [])))
      |> Enum.map(&normalize_data_ref/1)
    end)
    |> Enum.reject(&is_nil(&1.reference))
    |> Enum.uniq()
    |> Enum.sort_by(fn ref ->
      {ref.reference, ref.class || "", to_string(ref.sensitive), ref.key || ""}
    end)
  end

  defp direct_reference?(sink, reference) do
    sink
    |> Map.get(:data_refs, Map.get(sink, :pii, []))
    |> Enum.any?(fn data_ref ->
      (Map.get(data_ref, :reference) || Map.get(data_ref, "reference")) == reference
    end)
  end

  defp possible_pii?(sink) do
    value = Map.get(sink, :confidence)
    is_number(value) and value <= 0.7
  end

  defp node_has_reference?(node, reference) do
    node
    |> Map.get(:data_refs, Map.get(node, :pii, []))
    |> Enum.any?(fn data_ref ->
      (Map.get(data_ref, :reference) || Map.get(data_ref, "reference")) == reference
    end)
  end

  defp normalize_data_ref(data_ref) when is_map(data_ref) do
    reference =
      data_ref
      |> Map.get(:reference, Map.get(data_ref, "reference"))
      |> normalize_string()

    sensitive = Map.get(data_ref, :sensitive, Map.get(data_ref, "sensitive"))

    %{
      reference: reference,
      key: data_ref |> Map.get(:key, Map.get(data_ref, "key")) |> normalize_string(),
      class: data_ref |> Map.get(:class, Map.get(data_ref, "class")) |> normalize_string(),
      sensitive: sensitive in [true, "true"]
    }
  end

  defp normalize_data_ref(_), do: %{reference: nil, key: nil, class: nil, sensitive: false}

  defp group_key(node) do
    context = Map.get(node, :code_context, %{})
    module_name = Map.get(context, :module)
    function_name = Map.get(context, :function)
    file_path = Map.get(context, :file_path)

    if blank?(module_name) or blank?(function_name) or blank?(file_path) do
      nil
    else
      {module_name, function_name, file_path}
    end
  end

  defp entrypoint_for_group({module_name, function_name, _file_path}, nodes) do
    entrypoint_module =
      nodes
      |> Enum.find(fn node -> Map.get(node, :node_type) == "entrypoint" end)
      |> case do
        nil -> module_name
        node -> node |> Map.get(:code_context, %{}) |> Map.get(:module) || module_name
      end

    entrypoint_function =
      nodes
      |> Enum.find(fn node -> Map.get(node, :node_type) == "entrypoint" end)
      |> case do
        nil -> function_name
        node -> node |> Map.get(:code_context, %{}) |> Map.get(:function) || function_name
      end

    "#{entrypoint_module}.#{entrypoint_function}"
  end

  defp role_value(node, key) do
    node
    |> Map.get(:role, %{})
    |> Map.get(key)
  end

  defp boundary_for_kind(kind) do
    if MapSet.member?(@external_sink_kinds, normalize_kind(kind)) do
      "external"
    else
      "internal"
    end
  end

  defp normalize_kind(nil), do: "unknown"
  defp normalize_kind(value), do: value |> to_string() |> String.trim() |> String.downcase()

  defp normalize_subtype(nil), do: "unknown"

  defp normalize_subtype(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> "unknown"
      subtype -> subtype
    end
  end

  defp node_id(node), do: Map.get(node, :id) || Map.get(node, "id")

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_), do: false

  defp normalize_string(nil), do: nil

  defp normalize_string(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end
end
