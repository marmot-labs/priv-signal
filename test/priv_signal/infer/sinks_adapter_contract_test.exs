defmodule PrivSignal.Infer.SinksAdapterContractTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.NodeIdentity

  test "node identity remains deterministic for phase4 role kinds" do
    base_node = %{
      node_type: "sink",
      pii: [%{reference: "MyApp.Accounts.User.email", category: "contact", sensitivity: "medium"}],
      code_context: %{
        module: "MyApp.Module",
        function: "run/1",
        file_path: "lib/my_app/module.ex"
      },
      confidence: 0.7,
      evidence: []
    }

    ids =
      ["http", "http_response", "telemetry", "database_write", "liveview_render"]
      |> Enum.map(fn kind ->
        node = Map.put(base_node, :role, %{kind: kind, callee: "contract"})
        {kind, NodeIdentity.id(node)}
      end)

    assert Enum.count(ids) == 5
    assert Enum.uniq_by(ids, fn {_kind, id} -> id end) |> Enum.count() == 5
  end

  @tag :skip
  test "contract: scanner adapter maps category findings to role.kind values" do
    flunk("Enable in Phase 4 when unified scanner adapter is introduced")
  end

  @tag :skip
  test "contract: database read findings map to source node type" do
    flunk("Enable in Phase 4 when database scanner adapter mapping is implemented")
  end
end
