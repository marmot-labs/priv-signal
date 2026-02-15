defmodule PrivSignal.Score.TelemetryTest do
  use ExUnit.Case, async: false

  alias PrivSignal.Score.{Advisory, Engine}

  test "emits run/rule/advisory telemetry with low-cardinality metadata" do
    events = [
      [:priv_signal, :score, :run, :stop],
      [:priv_signal, :score, :rule_hit],
      [:priv_signal, :score, :advisory, :start],
      [:priv_signal, :score, :advisory, :stop],
      [:priv_signal, :score, :advisory, :error]
    ]

    :telemetry.attach_many("priv_signal-score-test", events, &__MODULE__.handle_event/4, self())

    diff = %{
      summary: %{total: 1},
      changes: [
        %{
          type: "flow_changed",
          flow_id: "payments",
          change: "external_sink_added",
          severity: "high",
          rule_id: "R-HIGH-EXTERNAL-SINK-ADDED",
          details: %{}
        }
      ]
    }

    assert {:ok, report} = Engine.run(diff, PrivSignal.Config.default_scoring())

    assert_received {:telemetry, [:priv_signal, :score, :run, :stop], measurements1, metadata1}
    assert is_integer(measurements1.points)
    assert metadata1.score in ["NONE", "LOW", "MEDIUM", "HIGH"]

    assert_received {:telemetry, [:priv_signal, :score, :rule_hit], measurements2, metadata2}
    assert measurements2.count >= 1
    assert is_binary(metadata2.rule_id)

    request_ok = fn _opts ->
      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [
             %{
               "message" => %{
                 "content" =>
                   Jason.encode!(%{
                     summary: "ok",
                     risk_assessment: "low",
                     suggested_review_focus: ["focus"]
                   })
               }
             }
           ]
         }
       }}
    end

    System.put_env("PRIV_SIGNAL_MODEL_API_KEY", "test-key")

    assert {:ok, _payload} =
             Advisory.run(diff, report, %{enabled: true, model: "gpt-5", timeout_ms: 5000},
               request: request_ok
             )

    assert_received {:telemetry, [:priv_signal, :score, :advisory, :start], _m3, _meta3}
    assert_received {:telemetry, [:priv_signal, :score, :advisory, :stop], _m4, meta4}
    assert meta4.ok == true

    request_error = fn _opts -> {:error, :timeout} end

    assert {:error, _reason} =
             Advisory.run(diff, report, %{enabled: true, model: "gpt-5", timeout_ms: 5000},
               request: request_error
             )

    assert_received {:telemetry, [:priv_signal, :score, :advisory, :error], _m5, meta5}
    assert meta5.ok == false
  after
    System.delete_env("PRIV_SIGNAL_MODEL_API_KEY")
    :telemetry.detach("priv_signal-score-test")
  end

  def handle_event(event, measurements, metadata, parent) do
    send(parent, {:telemetry, event, measurements, metadata})
  end
end
