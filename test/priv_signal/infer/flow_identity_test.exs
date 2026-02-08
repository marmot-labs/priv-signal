defmodule PrivSignal.Infer.FlowIdentityTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.FlowIdentity

  test "identity is stable when evidence and confidence change" do
    base = sample_flow()

    changed =
      base
      |> Map.put(:confidence, 0.31)
      |> Map.put(:evidence, Enum.reverse(base.evidence))

    assert FlowIdentity.id(base) == FlowIdentity.id(changed)
  end

  test "identity changes when semantic keys change" do
    base = sample_flow()

    refute FlowIdentity.id(base) == FlowIdentity.id(Map.put(base, :source, "MyApp.User.phone"))

    refute FlowIdentity.id(base) ==
             FlowIdentity.id(put_in(base, [:sink, :subtype], "Logger.warning"))
  end

  defp sample_flow do
    %{
      source: "MyApp.User.email",
      entrypoint: "MyAppWeb.UserController.create/2",
      sink: %{kind: "logger", subtype: "Logger.info"},
      boundary: "internal",
      confidence: 0.7,
      evidence: ["psn_a", "psn_b"]
    }
  end
end
