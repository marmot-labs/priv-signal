defmodule PrivSignal.Infer.NodeNormalizerTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.NodeNormalizer

  test "normalizes module/function/path and keeps lines as evidence-only metadata" do
    root = "/repo"

    raw = %{
      node_type: :SINK,
      data_refs: [
        %{reference: "MyApp.User.email", class: "direct_identifier", sensitive: true},
        %{reference: "MyApp.User.email", class: "direct_identifier", sensitive: true}
      ],
      code_context: %{
        module: "Elixir.MyApp.Accounts",
        function: " log_signup/2 ",
        file_path: "/repo/lib/my_app/accounts.ex",
        lines: [42, 42, 41]
      },
      role: %{kind: :LOGGER, callee: " Logger.info ", arity: 1},
      confidence: :confirmed,
      evidence: [
        %{
          rule: "logging_pii",
          signal: :field_access,
          finding_id: "abc123",
          line: 42,
          ast_kind: :call
        },
        %{
          rule: "logging_pii",
          signal: :field_access,
          finding_id: "abc123",
          line: 42,
          ast_kind: :call
        }
      ]
    }

    normalized = NodeNormalizer.normalize(raw, root: root)

    assert normalized.node_type == "sink"
    assert normalized.code_context.module == "MyApp.Accounts"
    assert normalized.code_context.function == "log_signup/2"
    assert normalized.code_context.file_path == "lib/my_app/accounts.ex"
    assert normalized.code_context.lines == [41, 42]
    assert normalized.role.kind == "logger"
    assert normalized.role.callee == "Logger.info"
    assert normalized.role.arity == 1
    assert normalized.confidence == 1.0
    assert length(normalized.data_refs) == 1
    assert length(normalized.evidence) == 1
    assert hd(normalized.evidence).finding_id == "abc123"
  end

  test "normalizes empty/missing fields safely" do
    normalized = NodeNormalizer.normalize(%{})

    assert normalized.node_type == nil
    assert normalized.code_context == %{module: nil, function: nil, file_path: nil}
    assert normalized.data_refs == []
    assert normalized.evidence == []
    assert normalized.role == %{kind: nil, callee: nil}
    assert normalized.confidence == 0.5
  end

  test "canonical_file_path keeps relative paths and normalizes separators" do
    assert NodeNormalizer.canonical_file_path("lib\\my_app\\x.ex", "/repo") == "lib/my_app/x.ex"
    assert NodeNormalizer.canonical_file_path("lib/my_app/x.ex", "/repo") == "lib/my_app/x.ex"
  end
end
