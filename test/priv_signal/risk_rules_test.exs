defmodule PrivSignal.Risk.RulesTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Risk.Rules

  defp event(type, id) do
    %{type: type, id: id, evidence: "lib/foo.ex:10", confidence: 0.9}
  end

  test "none when no events" do
    assert {:none, []} = Rules.categorize([])
  end

  test "low when flow touched only" do
    events = [event(:flow_touched, "flow")]
    assert {:low, reasons} = Rules.categorize(events)
    assert "Touches existing defined flow" in reasons
  end

  test "medium when new pii" do
    events = [event(:new_pii, "email")]
    assert {:medium, reasons} = Rules.categorize(events)
    assert "Introduces new PII categories" in reasons
  end

  test "high when new pii outside flows" do
    flows = [%{exits_system: false, third_party: nil}]
    events = [event(:new_pii, "email")]

    assert {:high, reasons} = Rules.categorize(events, flows: flows)
    assert "New PII usage outside defined flows" in reasons
  end

  test "high when sensitive data" do
    events = [event(:new_pii, "ssn")]
    assert {:high, reasons} = Rules.categorize(events)
    assert "Sensitive data categories detected" in reasons
  end

  test "high when new third-party transfer" do
    flows = [%{exits_system: true, third_party: "AWS S3"}]
    events = [event(:new_sink, "aws s3")]

    assert {:high, reasons} = Rules.categorize(events, flows: flows)
    assert "New third-party transfer" in reasons
  end
end
