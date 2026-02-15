defmodule PrivSignal.Score.AdvisoryTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.Advisory

  test "returns nil when advisory is disabled" do
    diff = %{summary: %{total: 0}}
    report = %{score: "NONE", reasons: []}

    assert {:ok, nil} =
             Advisory.run(diff, report, %{enabled: false, model: "gpt-5", timeout_ms: 1000})
  end

  test "returns advisory payload when enabled" do
    diff = %{summary: %{total: 1}}
    report = %{score: "LOW", reasons: [%{rule_id: "R2-LOW-PRIVACY-RELEVANT-RESIDUAL-CHANGE"}]}

    request = fn _opts ->
      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [
             %{
               "message" => %{
                 "content" =>
                   Jason.encode!(%{
                     summary: "Looks safe",
                     risk_assessment: "low",
                     suggested_review_focus: ["confirm sink"]
                   })
               }
             }
           ]
         }
       }}
    end

    llm = %{enabled: true, model: "gpt-5", timeout_ms: 5000}

    System.put_env("PRIV_SIGNAL_MODEL_API_KEY", "test-key")

    assert {:ok, payload} = Advisory.run(diff, report, llm, request: request)
    assert payload.summary == "Looks safe"
  after
    System.delete_env("PRIV_SIGNAL_MODEL_API_KEY")
  end

  test "returns error when model call fails" do
    diff = %{summary: %{total: 1}}
    report = %{score: "LOW", reasons: []}

    request = fn _opts -> {:error, :timeout} end

    llm = %{enabled: true, model: "gpt-5", timeout_ms: 5000}

    System.put_env("PRIV_SIGNAL_MODEL_API_KEY", "test-key")

    assert {:error, _reason} = Advisory.run(diff, report, llm, request: request)
  after
    System.delete_env("PRIV_SIGNAL_MODEL_API_KEY")
  end
end
