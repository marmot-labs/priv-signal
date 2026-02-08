defmodule PrivSignal.Infer.ScannerAdapter.Logging do
  @moduledoc false

  alias PrivSignal.Infer.{ModuleClassifier, Node, NodeIdentity, NodeNormalizer}

  def from_findings(findings, opts \\ []) when is_list(findings) do
    emit_entrypoints? = Keyword.get(opts, :emit_entrypoint_nodes, false)

    sink_nodes = Enum.map(findings, &sink_node_from_finding(&1, opts))

    entrypoint_nodes =
      if emit_entrypoints? do
        sink_nodes
        |> Enum.flat_map(&entrypoint_node_from_sink/1)
        |> Enum.uniq_by(& &1.id)
      else
        []
      end

    sink_nodes ++ entrypoint_nodes
  end

  defp sink_node_from_finding(finding, opts) do
    module_name = Map.get(finding, :module)
    file_path = Map.get(finding, :file)
    entrypoint = ModuleClassifier.classify(module_name, file_path, opts)

    node =
      %Node{
        node_type: "sink",
        pii: pii_from_finding(finding),
        code_context: %{
          module: module_name,
          function: function_with_arity(finding),
          file_path: file_path
        },
        role: %{
          kind: "logger",
          callee: canonical_callee(Map.get(finding, :sink)),
          arity: nil
        },
        confidence: confidence_value(Map.get(finding, :confidence)),
        evidence: evidence_from_finding(finding)
      }
      |> NodeNormalizer.normalize(opts)

    node =
      if entrypoint do
        Map.put(node, :entrypoint_context, %{
          kind: entrypoint.kind,
          confidence: entrypoint.confidence,
          evidence_signals: entrypoint.evidence_signals
        })
      else
        node
      end

    %{node | id: NodeIdentity.id(node, opts)}
  end

  defp entrypoint_node_from_sink(sink_node) do
    case Map.get(sink_node, :entrypoint_context) do
      %{kind: kind} = entrypoint when is_binary(kind) ->
        node =
          %Node{
            node_type: "entrypoint",
            pii: [],
            code_context: sink_node.code_context,
            role: %{
              kind: kind,
              callee: "module_classification",
              arity: nil
            },
            confidence: entrypoint.confidence,
            evidence: Enum.map(entrypoint.evidence_signals || [], &entrypoint_evidence/1)
          }
          |> NodeNormalizer.normalize()

        [%{node | id: NodeIdentity.id(node)}]

      _ ->
        []
    end
  end

  defp entrypoint_evidence(signal) do
    %{
      rule: "entrypoint_classification",
      signal: signal,
      finding_id: nil,
      line: nil,
      ast_kind: "heuristic"
    }
  end

  defp pii_from_finding(finding) do
    finding
    |> Map.get(:matched_fields, [])
    |> Enum.map(fn field ->
      module = Map.get(field, :module)
      name = Map.get(field, :name)

      %{
        reference: pii_reference(module, name),
        category: Map.get(field, :category),
        sensitivity: Map.get(field, :sensitivity)
      }
    end)
  end

  defp pii_reference(module, nil), do: module
  defp pii_reference(nil, name), do: name
  defp pii_reference(module, name), do: module <> "." <> name

  defp function_with_arity(finding) do
    function = Map.get(finding, :function)
    arity = Map.get(finding, :arity)

    cond do
      is_binary(function) and is_integer(arity) -> "#{function}/#{arity}"
      is_binary(function) -> function
      true -> nil
    end
  end

  defp confidence_value(:confirmed), do: 1.0
  defp confidence_value(:possible), do: 0.7
  defp confidence_value(value) when is_number(value), do: value
  defp confidence_value(_), do: 0.5

  defp evidence_from_finding(finding) do
    line = Map.get(finding, :line)
    finding_id = Map.get(finding, :id)

    finding
    |> Map.get(:evidence, [])
    |> Enum.map(fn evidence ->
      type = Map.get(evidence, :type)

      %{
        rule: "logging_pii",
        signal: if(is_atom(type), do: Atom.to_string(type), else: to_string(type || "unknown")),
        finding_id: finding_id,
        line: line,
        ast_kind: ast_kind(type)
      }
    end)
  end

  defp canonical_callee(nil), do: nil

  defp canonical_callee(callee) when is_binary(callee) do
    callee
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp canonical_callee(callee), do: to_string(callee)

  defp ast_kind(:direct_field_access), do: "field_access"
  defp ast_kind(:key_match), do: "key_match"
  defp ast_kind(:pii_container), do: "struct"
  defp ast_kind(:bulk_inspect), do: "call"
  defp ast_kind(_), do: "unknown"
end
