defmodule PrivSignal.Infer.NodeIdentityTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.NodeIdentity

  test "identity tuple excludes lines and evidence" do
    base = sample_node()

    changed =
      base
      |> put_in([:code_context, :lines], [999])
      |> Map.put(:evidence, [%{rule: "other", signal: "other", line: 999, ast_kind: "call"}])

    assert NodeIdentity.identity_tuple(base) == NodeIdentity.identity_tuple(changed)
    assert NodeIdentity.id(base) == NodeIdentity.id(changed)
  end

  test "identity changes for semantic tuple changes" do
    base = sample_node()

    changed_type = Map.put(base, :node_type, "entrypoint")
    changed_path = put_in(base, [:code_context, :file_path], "lib/my_app/other.ex")
    changed_role = put_in(base, [:role, :kind], "http")

    refute NodeIdentity.id(base) == NodeIdentity.id(changed_type)
    refute NodeIdentity.id(base) == NodeIdentity.id(changed_path)
    refute NodeIdentity.id(base) == NodeIdentity.id(changed_role)
  end

  defp sample_node do
    %{
      node_type: "sink",
      data_refs: [%{reference: "MyApp.User.email", class: "direct_identifier", sensitive: true}],
      code_context: %{
        module: "Elixir.MyApp.Accounts",
        function: "log_signup/2",
        file_path: "lib/my_app/accounts.ex",
        lines: [42]
      },
      role: %{kind: "logger", subtype: "Logger.info"},
      confidence: 1.0,
      evidence: [%{rule: "logging_pii", signal: "match", line: 42, ast_kind: "call"}]
    }
  end
end
