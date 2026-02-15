defmodule PrivSignal.Score.OutputJSONV2Test do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.Output.JSON

  test "emits v2 contract without points field" do
    rendered =
      JSON.render(
        %{
          score: "HIGH",
          summary: %{events_total: 2, events_high: 1, events_medium: 1, events_low: 0},
          reasons: [%{event_id: "evt:1", rule_id: "R2-HIGH-NEW-EXTERNAL-PII-EGRESS"}]
        },
        nil
      )

    assert rendered.version == "v2"
    assert rendered.score == "HIGH"
    assert is_map(rendered.summary)
    assert is_list(rendered.reasons)
    refute Map.has_key?(rendered, :points)
  end
end
