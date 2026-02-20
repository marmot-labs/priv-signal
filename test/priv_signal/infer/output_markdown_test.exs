defmodule PrivSignal.Infer.Output.MarkdownTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.Node
  alias PrivSignal.Infer.Output.Markdown

  test "renders markdown summary and node lines" do
    node = %Node{
      id: "psn_123",
      node_type: "sink",
      data_refs: [%{reference: "MyApp.User.email", class: "direct_identifier", sensitive: true}],
      code_context: %{
        module: "MyApp.Accounts",
        function: "log_signup/2",
        file_path: "lib/my_app/accounts.ex",
        lines: [42]
      },
      role: %{kind: "logger", callee: "Logger.info"},
      confidence: 1.0,
      evidence: []
    }

    markdown =
      Markdown.render(%{
        schema_version: "1",
        summary: %{node_count: 1, files_scanned: 1, scan_error_count: 0},
        nodes: [node],
        errors: []
      })

    assert String.contains?(markdown, "## PrivSignal Scan Lockfile")
    assert String.contains?(markdown, "**Node count:** 1")
    assert String.contains?(markdown, "[SINK] MyApp.Accounts.log_signup/2")
    assert String.contains?(markdown, "kind=logger")
  end

  test "renders operational errors when present" do
    markdown =
      Markdown.render(%{
        schema_version: "1",
        summary: %{node_count: 0, files_scanned: 1, scan_error_count: 1},
        nodes: [],
        errors: [%{file: "lib/broken.ex", reason: "failed to parse"}]
      })

    assert String.contains?(markdown, "No PRD evidence nodes were emitted.")
    assert String.contains?(markdown, "**Operational Errors:**")
    assert String.contains?(markdown, "lib/broken.ex: failed to parse")
  end
end
