defmodule PrivSignal.Infer.NodeIdentitySinksTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.NodeIdentity

  test "node identity differs across phase4 role kinds" do
    base = %{
      node_type: "sink",
      pii: [%{reference: "MyApp.User.email", category: "contact", sensitivity: "medium"}],
      code_context: %{
        module: "MyApp.Module",
        function: "run/1",
        file_path: "lib/my_app/module.ex"
      },
      confidence: 0.8,
      evidence: []
    }

    ids =
      ["http", "http_response", "telemetry", "database_write", "liveview_render"]
      |> Enum.map(fn kind ->
        node = Map.put(base, :role, %{kind: kind, callee: "callee"})
        NodeIdentity.id(node)
      end)

    assert length(ids) == 5
    assert Enum.uniq(ids) |> length() == 5
  end

  test "node type hint changes identity for database read source nodes" do
    sink_node = %{
      node_type: "sink",
      pii: [%{reference: "MyApp.User.email"}],
      code_context: %{
        module: "MyApp.Module",
        function: "run/1",
        file_path: "lib/my_app/module.ex"
      },
      role: %{kind: "database_read", callee: "Repo.get"},
      confidence: 1.0,
      evidence: []
    }

    source_node = Map.put(sink_node, :node_type, "source")

    refute NodeIdentity.id(sink_node) == NodeIdentity.id(source_node)
  end
end
