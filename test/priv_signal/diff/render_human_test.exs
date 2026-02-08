defmodule PrivSignal.Diff.Render.HumanTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Diff.Render.Human

  test "renders grouped severity sections and includes rule ids" do
    report = %{
      changes: [
        %{
          type: "flow_changed",
          flow_id: "flow_external",
          change: "external_sink_added",
          severity: "high",
          rule_id: "R-HIGH-EXTERNAL-SINK-ADDED",
          details: %{after_sink: %{kind: "mailgun", subtype: "send"}}
        },
        %{
          type: "flow_added",
          flow_id: "flow_internal",
          change: "flow_added",
          severity: "medium",
          rule_id: "R-MEDIUM-INTERNAL-FLOW-ADDED",
          details: %{sink: %{kind: "logger", subtype: "Logger.info"}, boundary: "internal"}
        },
        %{
          type: "confidence_changed",
          flow_id: "flow_conf",
          change: "confidence_changed",
          severity: "low",
          rule_id: "R-LOW-CONFIDENCE-ONLY",
          details: %{before_confidence: 0.2, after_confidence: 0.7}
        }
      ]
    }

    output = Human.render(report)

    assert String.contains?(output, "Privacy-Relevant Changes Detected")
    assert String.contains?(output, "HIGH:")
    assert String.contains?(output, "MEDIUM:")
    assert String.contains?(output, "LOW:")
    assert String.contains?(output, "[R-HIGH-EXTERNAL-SINK-ADDED]")
    assert String.contains?(output, "Confidence changed: flow_conf (0.2 -> 0.7)")
  end

  test "renders no-change state" do
    output = Human.render(%{changes: []})
    assert String.contains?(output, "No semantic privacy changes found")
  end
end
