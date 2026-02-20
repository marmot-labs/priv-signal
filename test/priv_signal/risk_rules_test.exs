defmodule PrivSignal.Risk.RulesTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Risk.Rules

  defp event(:flow_touched, id) do
    %{type: :flow_touched, flow_id: id, evidence: "lib/foo.ex:10", confidence: 0.9}
  end

  defp event(:new_pii, id) do
    %{type: :new_pii, pii_category: id, evidence: "lib/foo.ex:10", confidence: 0.9}
  end

  defp event(:new_sink, id) do
    %{type: :new_sink, sink: id, evidence: "lib/foo.ex:10", confidence: 0.9}
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

  test "medium when new pii without sensitive category" do
    events = [event(:new_pii, "email")]

    assert {:medium, reasons} = Rules.categorize(events)
    assert "Introduces new PII categories" in reasons
  end

  test "high when sensitive data" do
    events = [event(:new_pii, "ssn")]
    assert {:high, reasons} = Rules.categorize(events)
    assert "Sensitive data categories detected" in reasons
  end

  test "medium when new sink lacks explicit external boundary signal" do
    events = [event(:new_sink, "aws s3")]

    assert {:medium, reasons} = Rules.categorize(events)
    assert "Introduces new sink/export" in reasons
  end
end
