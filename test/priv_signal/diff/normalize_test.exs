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
end
