defmodule PrivSignal.Score.DeterminismPropertyTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.Engine

  test "engine output is stable across change ordering and metadata noise" do
    baseline_diff = %{
      changes: [
        %{
          type: "flow_changed",
          flow_id: "payments",
          change: "external_sink_added",
          severity: "high",
          rule_id: "R-HIGH-EXTERNAL-SINK-ADDED",
          details: %{}
        },
        %{
          type: "flow_changed",
          flow_id: "users",
          change: "pii_fields_expanded",
          severity: "medium",
          rule_id: "R-MEDIUM-PII-EXPANDED",
          details: %{added_fields: ["email"]}
        },
        %{
          type: "flow_added",
          flow_id: "internal-log",
          change: "flow_added",
          severity: "medium",
          rule_id: "R-MEDIUM-INTERNAL-FLOW-ADDED",
          details: %{boundary: "internal"}
        }
      ]
    }

    config = PrivSignal.Config.default_scoring()

    assert {:ok, baseline} = Engine.run(baseline_diff, config)

    Enum.each(1..30, fn _ ->
      noisy_diff = %{
        changes:
          baseline_diff.changes
          |> Enum.shuffle()
          |> Enum.map(fn change ->
            change
            |> Map.put(:runtime_noise, :rand.uniform(1000))
            |> Map.put(:metadata, %{generated_at: "2026-02-15T00:00:00Z"})
          end)
      }

      assert {:ok, rerun} = Engine.run(noisy_diff, config)
      assert rerun == baseline
    end)
  end
end
