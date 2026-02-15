defmodule PrivSignal.Score.EngineV2Test do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.Engine

  test "produces v2 summary and deterministic reasons for high outcome" do
    diff = %{
      metadata: %{strict_mode: false},
      events: [
        %{
          event_id: "evt:h1",
          event_type: "destination_changed",
          boundary_after: "external",
          sensitivity_after: "high"
        },
        %{
          event_id: "evt:m1",
          event_type: "boundary_changed",
          boundary_before: "internal",
          boundary_after: "external",
          sensitivity_after: "medium"
        }
      ]
    }

    assert {:ok, report} = Engine.run(diff, PrivSignal.Config.default_scoring())
    assert report.score == "HIGH"
    assert report.summary.events_total == 2
    assert report.summary.events_high == 1
    assert report.summary.events_medium == 1
    assert report.summary.events_low == 0

    assert report.reasons == [
             %{event_id: "evt:h1", rule_id: "R2-HIGH-NEW-VENDOR-HIGH-SENSITIVITY"}
           ]
  end

  test "fails closed in strict mode on unknown event type" do
    diff = %{
      metadata: %{strict_mode: true},
      events: [%{event_id: "evt:x", event_type: "not_known"}]
    }

    assert {:error, {:unknown_event_type, %{event_type: "not_known"}}} =
             Engine.run(diff, PrivSignal.Config.default_scoring())
  end
end
