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

  test "detects inferred attribute external transfer trigger" do
    data_nodes = [
      %{
        "key" => "risk_score",
        "name" => "Risk Score",
        "class" => "inferred_attribute",
        "sensitive" => false,
        "scope" => %{"module" => "Demo.Analytics", "field" => "risk_score"}
      }
    ]

    base =
      DiffFixtureHelper.build_artifact(
        [
          %{
            "id" => "flow_risk_score",
            "source" => "Demo.Analytics.risk_score",
            "source_key" => "risk_score",
            "source_class" => "inferred_attribute",
            "source_sensitive" => false,
            "entrypoint" => "Demo.Analytics.track/1",
            "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
            "boundary" => "internal",
            "confidence" => 0.7,
            "evidence" => ["node_risk"]
          }
        ],
        data_nodes: data_nodes
      )

    candidate =
      DiffFixtureHelper.build_artifact(
        [
          %{
            "id" => "flow_risk_score",
            "source" => "Demo.Analytics.risk_score",
            "source_key" => "risk_score",
            "source_class" => "inferred_attribute",
            "source_sensitive" => false,
            "entrypoint" => "Demo.Analytics.track/1",
            "sink" => %{"kind" => "http", "subtype" => "RiskAPI.send"},
            "boundary" => "external",
            "confidence" => 0.8,
            "evidence" => ["node_risk"]
          }
        ],
        data_nodes: data_nodes
      )

    changes = Semantic.compare(base, candidate)
    assert Enum.any?(changes, &(&1.change == "inferred_attribute_external_transfer"))
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
