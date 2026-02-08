defmodule PrivSignal.Diff.SemanticTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Diff.Semantic
  alias PrivSignal.Test.DiffFixtureHelper

  test "detects flow added" do
    base = DiffFixtureHelper.load_fixture!("flow_added", :base)
    candidate = DiffFixtureHelper.load_fixture!("flow_added", :candidate)

    assert [%{type: "flow_added", flow_id: "flow_export_roster_csv", change: "flow_added"}] =
             Semantic.compare(base, candidate)
             |> Enum.map(&Map.take(&1, [:type, :flow_id, :change]))
  end

  test "detects flow removed" do
    base = DiffFixtureHelper.load_fixture!("flow_removed", :base)
    candidate = DiffFixtureHelper.load_fixture!("flow_removed", :candidate)

    assert [
             %{
               type: "flow_removed",
               flow_id: "flow_legacy_enrollment_sync",
               change: "flow_removed"
             }
           ] =
             Semantic.compare(base, candidate)
             |> Enum.map(&Map.take(&1, [:type, :flow_id, :change]))
  end

  test "detects sink and boundary changes" do
    base = DiffFixtureHelper.load_fixture!("sink_changed", :base)
    candidate = DiffFixtureHelper.load_fixture!("sink_changed", :candidate)

    changes = Semantic.compare(base, candidate)

    assert Enum.any?(changes, &(&1.change == "external_sink_added"))
    assert Enum.any?(changes, &(&1.change == "boundary_changed"))
  end

  test "detects pii field expansion through source changes" do
    base = DiffFixtureHelper.load_fixture!("fields_changed", :base)
    candidate = DiffFixtureHelper.load_fixture!("fields_changed", :candidate)

    assert Enum.any?(Semantic.compare(base, candidate), &(&1.change == "pii_fields_expanded"))
  end

  test "confidence changes are optional" do
    base =
      DiffFixtureHelper.build_artifact([
        %{
          "id" => "flow_1",
          "source" => "Demo.User.email",
          "entrypoint" => "DemoWeb.UserController.create/2",
          "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
          "boundary" => "internal",
          "confidence" => 0.4,
          "evidence" => ["node_a"]
        }
      ])

    candidate =
      DiffFixtureHelper.build_artifact([
        %{
          "id" => "flow_1",
          "source" => "Demo.User.email",
          "entrypoint" => "DemoWeb.UserController.create/2",
          "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
          "boundary" => "internal",
          "confidence" => 0.8,
          "evidence" => ["node_a"]
        }
      ])

    refute Enum.any?(Semantic.compare(base, candidate), &(&1.type == "confidence_changed"))

    assert Enum.any?(
             Semantic.compare(base, candidate, include_confidence: true),
             &(&1.type == "confidence_changed")
           )
  end
end
