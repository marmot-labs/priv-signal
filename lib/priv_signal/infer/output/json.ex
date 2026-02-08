defmodule PrivSignal.Infer.Output.JSON do
  @moduledoc false

  alias PrivSignal.Infer.Contract

  def render(result) when is_map(result) do
    %{
      schema_version: Map.get(result, :schema_version, Contract.schema_version()),
      tool: Map.get(result, :tool, %{}),
      git: Map.get(result, :git, %{}),
      summary: Map.get(result, :summary, %{}),
      nodes: Enum.map(Map.get(result, :nodes, []), &render_node/1),
      flows: Enum.map(Map.get(result, :flows, []), &render_flow/1),
      errors: Map.get(result, :errors, [])
    }
  end

  defp render_node(node) do
    %{
      id: Map.get(node, :id),
      node_type: Map.get(node, :node_type),
      pii: Map.get(node, :pii, []),
      code_context: render_code_context(Map.get(node, :code_context, %{})),
      role: render_role(Map.get(node, :role, %{})),
      entrypoint_context: render_entrypoint_context(Map.get(node, :entrypoint_context)),
      confidence: Map.get(node, :confidence),
      evidence: Enum.map(Map.get(node, :evidence, []), &render_evidence/1)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp render_evidence(evidence) when is_map(evidence) do
    %{
      rule: Map.get(evidence, :rule),
      signal: Map.get(evidence, :signal),
      finding_id: Map.get(evidence, :finding_id),
      line: Map.get(evidence, :line),
      ast_kind: Map.get(evidence, :ast_kind)
    }
    |> compact_map()
  end

  defp render_entrypoint_context(nil), do: nil

  defp render_entrypoint_context(context) when is_map(context) do
    %{
      kind: Map.get(context, :kind),
      confidence: Map.get(context, :confidence),
      evidence_signals: Map.get(context, :evidence_signals, [])
    }
    |> compact_map()
  end

  defp render_flow(flow) when is_map(flow) do
    %{
      id: Map.get(flow, :id),
      source: Map.get(flow, :source),
      entrypoint: Map.get(flow, :entrypoint),
      sink: render_flow_sink(Map.get(flow, :sink, %{})),
      boundary: Map.get(flow, :boundary),
      confidence: Map.get(flow, :confidence),
      evidence: Map.get(flow, :evidence, [])
    }
    |> compact_map()
  end

  defp render_flow_sink(sink) when is_map(sink) do
    %{
      kind: Map.get(sink, :kind),
      subtype: Map.get(sink, :subtype)
    }
    |> compact_map()
  end

  defp render_code_context(context) when is_map(context) do
    %{
      module: Map.get(context, :module),
      function: Map.get(context, :function),
      file_path: Map.get(context, :file_path),
      lines: Map.get(context, :lines)
    }
    |> compact_map()
  end

  defp render_role(role) when is_map(role) do
    %{
      kind: Map.get(role, :kind),
      callee: Map.get(role, :callee),
      arity: Map.get(role, :arity)
    }
    |> compact_map()
  end

  defp compact_map(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
