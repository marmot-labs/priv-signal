defmodule PrivSignal.Score.EngineTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.Engine

  test "produces deterministic score report" do
    diff = %{
      changes: [
        %{
          type: "flow_changed",
          flow_id: "users",
          change: "pii_fields_expanded",
          severity: "medium",
          rule_id: "R-MEDIUM-PII-EXPANDED",
          details: %{added_fields: ["email"]}
        },
        %{
          type: "flow_changed",
          flow_id: "payments",
          change: "external_sink_added",
          severity: "high",
          rule_id: "R-HIGH-EXTERNAL-SINK-ADDED",
          details: %{}
        }
      ]
    }

    config = PrivSignal.Config.default_scoring()

    assert {:ok, report} = Engine.run(diff, config)
    assert report.score == "HIGH"
    assert report.points == 9
    assert report.summary.relevant_changes == 2
    assert length(report.reasons) == 2
  end
end
