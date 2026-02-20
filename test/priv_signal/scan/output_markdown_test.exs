defmodule PrivSignal.Scan.Output.MarkdownTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Scan.Finding
  alias PrivSignal.Scan.Output.Markdown

  test "renders summary, findings, and operational errors" do
    finding = %Finding{
      id: "abc123",
      classification: :confirmed_prd,
      confidence: :confirmed,
      sensitivity: :high,
      module: "MyApp.Auth",
      function: "login",
      arity: 2,
      file: "lib/my_app/auth.ex",
      line: 84,
      sink: "Logger.info",
      matched_nodes: [%{field: "email"}]
    }

    result = %{
      scanner_version: "1",
      summary: %{
        confirmed_count: 1,
        possible_count: 0,
        high_sensitivity_count: 1,
        files_scanned: 10,
        errors: 1
      },
      findings: [finding],
      errors: [%{file: "lib/bad.ex", reason: "failed to parse"}]
    }

    output = Markdown.render(result)

    assert String.contains?(output, "PrivSignal PRD Scan")
    assert String.contains?(output, "Confirmed findings:** 1")
    assert String.contains?(output, "[HIGH]")
    assert String.contains?(output, "lib/bad.ex: failed to parse")
  end
end
