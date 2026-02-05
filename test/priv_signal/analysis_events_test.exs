defmodule PrivSignal.Analysis.EventsTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Analysis.Events

  test "builds events from payload" do
    payload = %{
      "touched_flows" => [
        %{"flow_id" => "flow", "evidence" => "lib/foo.ex:10", "confidence" => 0.7}
      ],
      "new_pii" => [
        %{"pii_category" => "email", "evidence" => "lib/foo.ex:11", "confidence" => 0.6}
      ],
      "new_sinks" => [%{"sink" => "s3", "evidence" => "lib/foo.ex:12", "confidence" => 0.8}],
      "notes" => []
    }

    events = Events.from_payload(payload)

    assert Enum.any?(events, &match?(%{type: :flow_touched, flow_id: "flow"}, &1))
    assert Enum.any?(events, &match?(%{type: :new_pii, pii_category: "email"}, &1))
    assert Enum.any?(events, &match?(%{type: :new_sink, sink: "s3"}, &1))
  end
end
