defmodule PrivSignal.Score.DecisionOrderV2Test do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.Engine

  test "empty events yields NONE" do
    diff = %{metadata: %{strict_mode: false}, events: []}
    assert {:ok, report} = Engine.run(diff, PrivSignal.Config.default_scoring())
    assert report.score == "NONE"
    assert report.reasons == []
  end

  test "any high takes precedence over medium" do
    diff = %{
      metadata: %{strict_mode: false},
      events: [
        %{
          event_id: "evt:m",
          event_type: "boundary_changed",
          boundary_before: "internal",
          boundary_after: "external",
          sensitivity_after: "medium"
        },
        %{
          event_id: "evt:h",
          event_type: "destination_changed",
          boundary_after: "external",
          sensitivity_after: "high"
        }
      ]
    }

    assert {:ok, report} = Engine.run(diff, PrivSignal.Config.default_scoring())
    assert report.score == "HIGH"
    assert Enum.all?(report.reasons, &(&1.rule_id == "R2-HIGH-NEW-VENDOR-HIGH-SENSITIVITY"))
  end

  test "medium is selected when no high exists" do
    diff = %{
      metadata: %{strict_mode: false},
      events: [
        %{
          event_id: "evt:m",
          event_type: "boundary_changed",
          boundary_before: "internal",
          boundary_after: "external",
          sensitivity_after: "medium"
        }
      ]
    }

    assert {:ok, report} = Engine.run(diff, PrivSignal.Config.default_scoring())
    assert report.score == "MEDIUM"
  end

  test "non-empty low-only events yields LOW" do
    diff = %{
      metadata: %{strict_mode: false},
      events: [
        %{event_id: "evt:l", event_type: "edge_removed"}
      ]
    }

    assert {:ok, report} = Engine.run(diff, PrivSignal.Config.default_scoring())
    assert report.score == "LOW"

    assert report.reasons == [
             %{event_id: "evt:l", rule_id: "R2-LOW-PRIVACY-RELEVANT-RESIDUAL-CHANGE"}
           ]
  end
end
