defmodule PrivSignal.Infer.Output.JSONTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.Node
  alias PrivSignal.Infer.Output.JSON

  test "renders infer result envelope with summary and node payload" do
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
      role: %{kind: "logger", callee: "Logger.info", arity: 1},
      confidence: 1.0,
      evidence: [
        %{
          rule: "logging_pii",
          signal: "direct_field_access",
          finding_id: "f123",
          line: 42,
          ast_kind: "call"
        }
      ]
    }

    result = %{
      schema_version: "1.2",
      tool: %{name: "priv_signal", version: "0.1.0"},
      git: %{commit: "abc123"},
      summary: %{node_count: 1, files_scanned: 1, scan_error_count: 0},
      nodes: [node],
      flows: [
        %{
          id: "psf_123",
          source: "MyApp.User.email",
          entrypoint: "MyApp.Accounts.log_signup/2",
          sink: %{kind: "logger", subtype: "Logger.info"},
          boundary: "internal",
          confidence: 0.9,
          evidence: ["psn_123"]
        }
      ],
      errors: []
    }

    rendered = JSON.render(result)

    assert rendered.schema_version == "1.2"
    assert rendered.summary.node_count == 1
    assert length(rendered.nodes) == 1
    assert length(rendered.flows) == 1

    [rendered_node] = rendered.nodes
    assert rendered_node.id == "psn_123"
    assert rendered_node.node_type == "sink"
    assert rendered_node.role.kind == "logger"
    assert rendered_node.role.callee == "Logger.info"
    assert rendered_node.role.arity == 1
    assert rendered_node.code_context.file_path == "lib/my_app/accounts.ex"
    assert hd(rendered_node.evidence).rule == "logging_pii"
    assert hd(rendered_node.evidence).finding_id == "f123"
    refute Map.has_key?(rendered, :edges)
  end

  test "drops nil entrypoint_context from node payload" do
    result = %{
      schema_version: "1.2",
      tool: %{},
      git: %{},
      summary: %{},
      nodes: [
        %{
          id: "psn_abc",
          node_type: "sink",
          data_refs: [],
          code_context: %{},
          role: %{},
          confidence: 0.5,
          evidence: [],
          entrypoint_context: nil
        }
      ],
      flows: [],
      errors: []
    }

    [node] = JSON.render(result).nodes
    refute Map.has_key?(node, :entrypoint_context)
  end
end
