defmodule PrivSignal.Score.RubricV2RulesTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.RubricV2

  test "maps high-risk destination changes to high class/rule" do
    event = %{
      event_id: "evt:1",
      event_type: "destination_changed",
      boundary_after: "external",
      sensitivity_after: "high"
    }

    assert {:ok, classified} = RubricV2.classify_event(event)
    assert classified.event_class == "high"
    assert classified.rule_id == "R2-HIGH-NEW-VENDOR-HIGH-SENSITIVITY"
  end

  test "maps boundary tier increase to medium class/rule" do
    event = %{
      event_id: "evt:2",
      event_type: "boundary_changed",
      boundary_before: "internal",
      boundary_after: "external",
      sensitivity_after: "medium"
    }

    assert {:ok, classified} = RubricV2.classify_event(event)
    assert classified.event_class == "medium"
    assert classified.rule_id == "R2-MEDIUM-BOUNDARY-TIER-INCREASE"
  end

  test "maps unknown event_type to warning+low in non-strict mode" do
    event = %{event_id: "evt:3", event_type: "unseen_event"}

    assert {:warn, classified, _warning} = RubricV2.classify_event(event, strict: false)
    assert classified.event_class == "low"
    assert classified.unknown_event_type == true
  end
end
