defmodule PrivSignal.Score.EngineTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.Engine

  test "produces deterministic score report" do
    diff = %{
      metadata: %{strict_mode: false},
      events: [
        %{
          event_id: "evt:users",
          event_type: "boundary_changed",
          boundary_before: "internal",
          boundary_after: "external",
          sensitivity_after: "medium"
        },
        %{
          event_id: "evt:payments",
          event_type: "destination_changed",
          boundary_after: "external",
          sensitivity_after: "high"
        }
      ]
    }

    config = PrivSignal.Config.default_scoring()

    assert {:ok, report} = Engine.run(diff, config)
    assert report.score == "HIGH"
    assert report.summary.events_total == 2
    assert report.summary.events_high == 1
    assert length(report.reasons) == 1
  end
end
