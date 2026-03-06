defmodule PrivSignal.Diff.NormalizeTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Diff.Normalize
  alias PrivSignal.Test.DiffFixtureHelper

  test "normalization is insensitive to flow ordering and metadata noise" do
    base = DiffFixtureHelper.load_fixture!("no_change", :base)
    [flow] = base["flows"]

    noisy =
      base
      |> Map.put("summary", %{"changed" => true, "timestamp" => "2026-02-08T12:00:00Z"})
      |> Map.put("errors", ["transient"])
      |> Map.put("flows", [
        flow
        |> Map.put("evidence", Enum.reverse(flow["evidence"]))
        |> Map.put("unknown", "ignored")
      ])

    assert Normalize.normalize(base) == Normalize.normalize(noisy)
  end

  test "normalization canonicalizes evidence and boundary" do
    artifact = %{
      "schema_version" => "1.2",
      "flows" => [
        %{
          "id" => "flow_1",
          "source" => " Demo.User.email ",
          "entrypoint" => "DemoWeb.UserController.create/2",
          "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
          "boundary" => " EXTERNAL ",
          "confidence" => "0.9000",
          "evidence" => ["b", "a", "a"]
        }
      ]
    }

    normalized = Normalize.normalize(artifact)
    [flow] = normalized.flows

    assert flow.boundary == "external"
    assert flow.source == "Demo.User.email"
    assert flow.confidence == 0.9
    assert flow.evidence == ["a", "b"]
  end

  test "normalization derives flow location from evidence nodes" do
    artifact = %{
      "schema_version" => "1.2",
      "nodes" => [
        %{
          "id" => "source_node",
          "node_type" => "source",
          "code_context" => %{
            "module" => "Demo.Accounts",
            "function" => "register/1",
            "file_path" => "lib/demo/accounts.ex",
            "lines" => [12]
          },
          "evidence" => [%{"line" => 12}]
        },
        %{
          "id" => "sink_node",
          "node_type" => "sink",
          "code_context" => %{
            "module" => "Demo.Accounts",
            "function" => "register/1",
            "file_path" => "lib/demo/accounts.ex",
            "lines" => [44]
          },
          "evidence" => [%{"line" => 44}]
        }
      ],
      "flows" => [
        %{
          "id" => "flow_1",
          "source" => "Demo.User.email",
          "entrypoint" => "Demo.Accounts.register/1",
          "sink" => %{"kind" => "http", "subtype" => "Req.post!/2"},
          "boundary" => "external",
          "confidence" => 0.9,
          "evidence" => ["source_node", "sink_node"]
        }
      ]
    }

    normalized = Normalize.normalize(artifact)
    [flow] = normalized.flows

    assert flow.location == %{file_path: "lib/demo/accounts.ex", line: 44}
  end
end
