defmodule PrivSignal.Scan.Output.JSON do
  @moduledoc false

  def render(result) when is_map(result) do
    %{
      scanner_version: result.scanner_version,
      path_mode: "repo_relative_posix_when_possible",
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
      file: normalize_file_path(finding.file),
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

  defp normalize_file_path(nil), do: nil

  defp normalize_file_path(path) when is_binary(path) do
    cwd = String.replace(File.cwd!(), "\\", "/")
    normalized_path = String.replace(path, "\\", "/")

    case Path.type(normalized_path) do
      :absolute ->
        case Path.relative_to(normalized_path, cwd) do
          relative when relative == normalized_path -> normalized_path
          relative -> relative
        end

      :relative ->
        normalized_path
    end
  end

  defp normalize_file_path(path), do: path
end
