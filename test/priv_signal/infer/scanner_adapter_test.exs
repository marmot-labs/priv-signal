defmodule PrivSignal.Infer.ScannerAdapterTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.ScannerAdapter.Logging

  test "maps category findings to role kinds and node types" do
    findings = [
      %{
        id: "f-http",
        module: "MyApp.HTTPClient",
        function: "send_data",
        arity: 1,
        file: "lib/my_app/http_client.ex",
        line: 10,
        role_kind: "http",
        sink: "Req.post",
        matched_nodes: [
          %{module: "MyApp.User", name: "email", class: "direct_identifier", sensitive: true}
        ],
        evidence: [%{type: :direct_field_access}],
        confidence_hint: 0.8
      },
      %{
        id: "f-db-read",
        module: "MyApp.Accounts",
        function: "load_user",
        arity: 1,
        file: "lib/my_app/accounts.ex",
        line: 20,
        role_kind: "database_read",
        node_type_hint: "source",
        sink: "Repo.get",
        matched_nodes: [
          %{module: "MyApp.User", name: "email", class: "direct_identifier", sensitive: true}
        ],
        evidence: [%{type: :key_match}],
        confidence_hint: 1.0
      },
      %{
        id: "f-lv",
        module: "MyAppWeb.UserLive",
        function: "handle_event",
        arity: 3,
        file: "lib/my_app_web/live/user_live.ex",
        line: 15,
        role_kind: "liveview_render",
        sink: "assign",
        matched_nodes: [
          %{module: "MyApp.User", name: "email", class: "direct_identifier", sensitive: true}
        ],
        evidence: [%{type: :token_match}],
        confidence_hint: 0.7
      }
    ]

    nodes = Logging.from_findings(findings, root: "/repo")

    assert length(nodes) == 3

    assert Enum.any?(nodes, fn node ->
             node.node_type == "sink" and node.role.kind == "http" and
               node.role.callee == "Req.post"
           end)

    assert Enum.any?(nodes, fn node ->
             node.node_type == "source" and node.role.kind == "database_read" and
               node.role.callee == "Repo.get"
           end)

    assert Enum.any?(nodes, fn node ->
             node.node_type == "sink" and node.role.kind == "liveview_render"
           end)

    assert Enum.all?(nodes, &is_binary(&1.id))
  end
end
