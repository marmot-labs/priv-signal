defmodule PrivSignal.Diff.ContractV2Test do
  use ExUnit.Case, async: true

  alias PrivSignal.Diff.{ContractV2, EventId}

  @moduledoc """
  Contract tests for Diff v2 JSON event payloads.
  """

  test "requires diff renderer schema version v2 and events array" do
    events = [
      %{
        event_id: EventId.generate(%{event_type: "edge_added", edge_id: "flow_1"}),
        event_type: "edge_added",
        event_class: "medium",
        edge_id: "flow_1"
      }
    ]

    assert {:ok, []} = ContractV2.validate_events(events, strict: true)
  end

  test "enforces deterministic ordering for events[] with frozen sort keys" do
    events = [
      %{
        event_id: "evt:b",
        event_type: "edge_added",
        event_class: "medium",
        edge_id: "flow_2"
      },
      %{
        event_id: "evt:a",
        event_type: "destination_changed",
        event_class: "high",
        edge_id: "flow_1"
      }
    ]

    assert {:ok, []} = ContractV2.validate_events(events, strict: true)
  end
end
