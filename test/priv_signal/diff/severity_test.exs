defmodule PrivSignal.Diff.SeverityTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Diff.Severity

  test "applies high severity to external sink and boundary exits" do
    changes = [
      %{
        type: "flow_changed",
        flow_id: "flow_1",
        change: "external_sink_added",
        details: %{after_sink: %{kind: "mailgun", subtype: "send"}}
      },
      %{
        type: "flow_changed",
        flow_id: "flow_2",
        change: "boundary_changed",
        details: %{before_boundary: "internal", after_boundary: "external"}
      }
    ]

    annotated = Severity.annotate(changes)

    assert Enum.any?(
             annotated,
             &(&1.rule_id == "R-HIGH-EXTERNAL-SINK-ADDED" and &1.severity == "high")
           )

    assert Enum.any?(
             annotated,
             &(&1.rule_id == "R-HIGH-BOUNDARY-EXITS-SYSTEM" and &1.severity == "high")
           )
  end

  test "applies medium/low severities to representative rules" do
    changes = [
      %{
        type: "flow_added",
        flow_id: "flow_1",
        change: "flow_added",
        details: %{boundary: "internal"}
      },
      %{
        type: "flow_removed",
        flow_id: "flow_2",
        change: "flow_removed",
        details: %{}
      },
      %{
        type: "confidence_changed",
        flow_id: "flow_3",
        change: "confidence_changed",
        details: %{before_confidence: 0.2, after_confidence: 0.8}
      }
    ]

    annotated = Severity.annotate(changes)

    assert Enum.any?(
             annotated,
             &(&1.rule_id == "R-MEDIUM-INTERNAL-FLOW-ADDED" and &1.severity == "medium")
           )

    assert Enum.any?(annotated, &(&1.rule_id == "R-LOW-FLOW-REMOVED" and &1.severity == "low"))
    assert Enum.any?(annotated, &(&1.rule_id == "R-LOW-CONFIDENCE-ONLY" and &1.severity == "low"))
  end

  test "applies high priority tie-break in deterministic sorting order" do
    changes = [
      %{type: "flow_removed", flow_id: "z_flow", change: "flow_removed", details: %{}},
      %{
        type: "flow_changed",
        flow_id: "a_flow",
        change: "external_sink_added",
        details: %{after_sink: %{kind: "mailgun", subtype: "send"}}
      },
      %{
        type: "flow_added",
        flow_id: "m_flow",
        change: "flow_added",
        details: %{boundary: "internal"}
      }
    ]

    [first | _] = Severity.annotate(changes)
    assert first.severity == "high"
    assert first.flow_id == "a_flow"
  end
end
