defmodule PrivSignal.Score.PerfV2BaselineTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.Engine

  test "score run over 10k v2 events stays within baseline envelope" do
    diff = %{
      metadata: %{strict_mode: false},
      events: build_events(10_000)
    }

    # Warmup
    assert {:ok, _} = Engine.run(diff, PrivSignal.Config.default_scoring())

    {durations_ms, memory_deltas} =
      Enum.reduce(1..3, {[], []}, fn _, {dur_acc, mem_acc} ->
        before_mem = :erlang.memory(:total)
        start = System.monotonic_time()
        assert {:ok, report} = Engine.run(diff, PrivSignal.Config.default_scoring())
        duration_ms = elapsed_ms(start)
        after_mem = :erlang.memory(:total)

        assert report.summary.events_total == 10_000
        assert report.score in ["LOW", "MEDIUM", "HIGH"]

        {dur_acc ++ [duration_ms], mem_acc ++ [max(after_mem - before_mem, 0)]}
      end)

    p95_ms = percentile_95(durations_ms)
    max_mem_delta = Enum.max(memory_deltas)

    assert p95_ms <= 3_000
    assert max_mem_delta <= 200 * 1024 * 1024
  end

  defp build_events(count) do
    Enum.map(1..count, fn i ->
      case rem(i, 4) do
        0 ->
          %{
            event_id: "evt:h:#{i}",
            event_type: "destination_changed",
            boundary_after: "external",
            sensitivity_after: "high"
          }

        1 ->
          %{
            event_id: "evt:m:#{i}",
            event_type: "boundary_changed",
            boundary_before: "internal",
            boundary_after: "external",
            sensitivity_after: "medium"
          }

        2 ->
          %{
            event_id: "evt:l:#{i}",
            event_type: "edge_removed"
          }

        _ ->
          %{
            event_id: "evt:u:#{i}",
            event_type: "unknown_event",
            details: %{}
          }
      end
    end)
  end

  defp percentile_95(values) do
    sorted = Enum.sort(values)
    idx = max(0, ceil(length(sorted) * 0.95) - 1)
    Enum.at(sorted, idx, 0)
  end

  defp elapsed_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end
end
