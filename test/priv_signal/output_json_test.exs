defmodule PrivSignal.Output.JSONTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Output.JSON

  test "renders JSON map" do
    result = %{category: :low, reasons: ["Touches existing defined flow"], events: []}

    json = JSON.render(result)

    assert json.risk_category == :low
    assert json.reasons == ["Touches existing defined flow"]
  end
end
