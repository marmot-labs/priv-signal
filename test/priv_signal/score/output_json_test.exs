defmodule PrivSignal.Score.Output.JSONTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.Output.JSON

  test "renders stable score json contract" do
    report = %{
      score: "MEDIUM",
      summary: %{events_total: 1},
      reasons: [%{rule_id: "R2-1", event_id: "evt:abc"}]
    }

    rendered = JSON.render(report, %{summary: "advisory"})

    assert rendered.version == "v2"
    assert rendered.score == "MEDIUM"
    refute Map.has_key?(rendered, :points)
    assert rendered.llm_interpretation.summary == "advisory"
  end
end
