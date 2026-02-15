defmodule PrivSignal.Diff.EventIdDeterminismTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Diff.EventId

  test "event_id is deterministic for identical event payloads" do
    event = %{
      event_type: "edge_added",
      event_class: "medium",
      rule_id: "R2-MEDIUM-NEW-INTERNAL-SINK",
      edge_id: "flow_1",
      details: %{"b" => 2, "a" => 1}
    }

    assert EventId.generate(event) == EventId.generate(event)
  end

  test "event_id changes when semantic identity changes" do
    event_a = %{
      event_type: "edge_added",
      event_class: "medium",
      rule_id: "R2-MEDIUM-NEW-INTERNAL-SINK",
      edge_id: "flow_1",
      details: %{"a" => 1}
    }

    event_b = %{event_a | edge_id: "flow_2"}

    refute EventId.generate(event_a) == EventId.generate(event_b)
  end
end
