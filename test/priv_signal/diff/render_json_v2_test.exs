defmodule PrivSignal.Diff.Render.JSONV2Test do
  use ExUnit.Case, async: true

  alias PrivSignal.Diff.Render.JSON

  test "renders stable v2 json contract with events summary counts" do
    report = %{
      metadata: %{
        base_ref: "origin/main",
        schema_version_base: "1.2",
        schema_version_candidate: "1.2"
      },
      events: [
        %{
          event_id: "evt:b",
          event_type: "edge_removed",
          event_class: "low",
          rule_id: "R2-LOW-PRIVACY-RELEVANT-RESIDUAL-CHANGE",
          node_id: nil,
          edge_id: "z_flow",
          details: %{}
        },
        %{
          event_id: "evt:a",
          event_type: "destination_changed",
          event_class: "high",
          rule_id: "R2-HIGH-NEW-EXTERNAL-PII-EGRESS",
          node_id: nil,
          edge_id: "a_flow",
          details: %{}
        }
      ]
    }

    rendered = JSON.render(report)

    assert rendered.version == "v2"
    assert rendered.summary.events_total == 2
    assert rendered.summary.events_high == 1
    assert rendered.summary.events_low == 1
    assert rendered.summary.events_medium == 0

    [first | _] = rendered.events
    assert first.event_class == "high"
    assert first.edge_id == "a_flow"
  end

  test "schema version is explicit and stable for v2" do
    assert JSON.schema_version() == "v2"
  end
end
