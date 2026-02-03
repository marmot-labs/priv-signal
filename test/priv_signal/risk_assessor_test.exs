defmodule PrivSignal.Risk.AssessorTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Risk.Assessor

  test "assess returns category and reasons" do
    events = [%{type: :flow_touched, id: "flow", evidence: "lib/foo.ex:10", confidence: 0.9}]

    result = Assessor.assess(events)

    assert result.category == :low
    assert "Touches existing defined flow" in result.reasons
    assert result.events == events
  end
end
