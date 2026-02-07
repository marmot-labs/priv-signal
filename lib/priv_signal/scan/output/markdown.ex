defmodule PrivSignal.Scan.Output.Markdown do
  @moduledoc false

  def render(result) when is_map(result) do
    summary = result.summary || %{}
    findings = result.findings || []
    errors = result.errors || []

    lines = [
      "## PrivSignal PII Scan",
      "",
      "**Scanner version:** #{result.scanner_version}",
      "**Files scanned:** #{summary.files_scanned || 0}",
      "**Confirmed findings:** #{summary.confirmed_count || 0}",
      "**Possible findings:** #{summary.possible_count || 0}",
      "**High sensitivity findings:** #{summary.high_sensitivity_count || 0}",
      "**Scan errors:** #{summary.errors || 0}"
    ]

    lines =
      if findings == [] do
        lines ++ ["", "No PII-relevant logging findings detected."]
      else
        lines ++ ["", "**Findings:**", "" | Enum.map(findings, &format_finding/1)]
      end

    lines =
      if errors == [] do
        lines
      else
        lines ++ ["", "**Operational Errors:**", "" | Enum.map(errors, &format_error/1)]
      end

    Enum.join(lines, "\n")
  end

  defp format_finding(finding) do
    location =
      "#{finding.module}.#{finding.function}/#{finding.arity} (#{finding.file}:#{finding.line})"

    fields = Enum.map_join(finding.matched_fields || [], ", ", & &1.name)

    "- [#{format_severity(finding)}] #{location} via #{finding.sink} (fields: #{fields})"
  end

  defp format_error(error) do
    file = error[:file] || "unknown_file"
    reason = error[:reason] || "unknown_reason"
    "- #{file}: #{reason}"
  end

  defp format_severity(%{classification: :confirmed_pii, sensitivity: :high}), do: "HIGH"
  defp format_severity(%{classification: :confirmed_pii}), do: "MEDIUM"
  defp format_severity(_), do: "LOW"
end
