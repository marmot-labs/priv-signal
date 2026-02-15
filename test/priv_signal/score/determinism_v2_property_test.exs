defmodule PrivSignal.Score.DeterminismV2PropertyTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.Engine

  test "v2 output is stable across event ordering and metadata noise" do
    baseline_diff = %{
      metadata: %{strict_mode: false},
      events: [
        %{
          event_id: "evt:h",
          event_type: "destination_changed",
          boundary_after: "external",
          sensitivity_after: "high",
          details: %{}
        },
        %{
          event_id: "evt:m",
          event_type: "boundary_changed",
          boundary_before: "internal",
          boundary_after: "external",
          sensitivity_after: "medium",
          details: %{}
        },
        %{event_id: "evt:l", event_type: "edge_removed", details: %{}}
      ]
    }

    assert {:ok, baseline} = Engine.run(baseline_diff, PrivSignal.Config.default_scoring())

    Enum.each(1..30, fn _ ->
      noisy_diff = %{
        metadata: %{
          strict_mode: false,
          generated_at: "2026-02-15T00:00:00Z",
          noise: :rand.uniform(1000)
        },
        events:
          baseline_diff.events
          |> Enum.shuffle()
          |> Enum.map(fn event ->
            Map.put(event, :runtime_noise, :rand.uniform(1000))
          end)
      }

      assert {:ok, rerun} = Engine.run(noisy_diff, PrivSignal.Config.default_scoring())
      assert rerun == baseline
    end)
  end
end
