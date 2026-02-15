defmodule PrivSignal.Score.DeterminismPropertyTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.Engine

  test "engine output is stable across event ordering and metadata noise" do
    baseline_diff = %{
      metadata: %{strict_mode: false},
      events: [
        %{
          event_id: "evt:payments",
          event_type: "destination_changed",
          boundary_after: "external",
          sensitivity_after: "high"
        },
        %{
          event_id: "evt:users",
          event_type: "boundary_changed",
          boundary_before: "internal",
          boundary_after: "external",
          sensitivity_after: "medium"
        },
        %{event_id: "evt:low", event_type: "edge_removed"}
      ]
    }

    config = PrivSignal.Config.default_scoring()

    assert {:ok, baseline} = Engine.run(baseline_diff, config)

    Enum.each(1..30, fn _ ->
      noisy_diff = %{
        metadata: %{strict_mode: false},
        events:
          baseline_diff.events
          |> Enum.shuffle()
          |> Enum.map(fn event ->
            event
            |> Map.put(:runtime_noise, :rand.uniform(1000))
            |> Map.put(:metadata, %{generated_at: "2026-02-15T00:00:00Z"})
          end)
      }

      assert {:ok, rerun} = Engine.run(noisy_diff, config)
      assert rerun == baseline
    end)
  end
end
