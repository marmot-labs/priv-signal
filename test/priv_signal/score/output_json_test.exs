defmodule PrivSignal.Score.Output.JSONTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.Output.JSON

  test "renders stable score json contract" do
    report = %{
      score: "MEDIUM",
      points: 6,
      summary: %{nodes_added: 1},
      reasons: [%{rule_id: "R-1", points: 6, change_id: "flow:abc:flow_added"}]
    }

    rendered = JSON.render(report, %{summary: "advisory"})

    assert rendered.version == "v1"
    assert rendered.score == "MEDIUM"
    assert rendered.points == 6
    assert rendered.llm_interpretation.summary == "advisory"
  end
end
