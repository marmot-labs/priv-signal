defmodule PrivSignal.Score.RulesTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.Rules

  test "evaluates high external sink rule" do
    change = %{
      type: "flow_changed",
      flow_id: "payments",
      change: "external_sink_added",
      details: %{}
    }

    assert {:ok, reason} = Rules.evaluate(change)
    assert reason.rule_id == "R-HIGH-EXTERNAL-SINK-ADDED"
    assert reason.points == 6
  end

  test "ignores unknown events" do
    assert :ignore =
             Rules.evaluate(%{type: "unknown", flow_id: "x", change: "unknown", details: %{}})
  end
end
