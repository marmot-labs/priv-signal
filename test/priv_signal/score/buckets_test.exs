defmodule PrivSignal.Score.BucketsTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.Buckets

  test "maps points into default buckets" do
    assert Buckets.classify(0, 0, []) == "NONE"
    assert Buckets.classify(2, 1, []) == "LOW"
    assert Buckets.classify(5, 1, []) == "MEDIUM"
    assert Buckets.classify(9, 1, []) == "HIGH"
  end

  test "applies floor escalation for external sink rules" do
    reasons = [%{rule_id: "R-HIGH-EXTERNAL-SINK-ADDED", severity: "high"}]
    assert Buckets.classify(1, 1, reasons) == "HIGH"
  end
end
