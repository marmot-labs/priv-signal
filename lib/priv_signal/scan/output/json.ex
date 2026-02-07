defmodule PrivSignal.Scan.Output.JSON do
  @moduledoc false

  def render(result) when is_map(result) do
    %{
      scanner_version: result.scanner_version,
      summary: result.summary,
      inventory: result.inventory,
      findings: Enum.map(result.findings || [], &render_finding/1),
      errors: result.errors || []
    }
  end

  defp render_finding(finding) do
    %{
      id: finding.id,
      classification: finding.classification,
      confidence: finding.confidence,
      sensitivity: finding.sensitivity,
      module: finding.module,
      function: finding.function,
      arity: finding.arity,
      file: finding.file,
      line: finding.line,
      sink: finding.sink,
      matched_fields: finding.matched_fields,
      evidence: Enum.map(finding.evidence || [], &render_evidence/1)
    }
  end

  defp render_evidence(evidence) do
    %{
      type: evidence.type,
      expression: evidence.expression,
      fields: evidence.fields
    }
  end
end
