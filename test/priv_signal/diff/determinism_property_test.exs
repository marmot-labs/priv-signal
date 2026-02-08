defmodule PrivSignal.Diff.DeterminismPropertyTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Diff.Semantic
  alias PrivSignal.Test.DiffFixtureHelper

  test "semantic output is stable across ordering and metadata noise" do
    base = DiffFixtureHelper.load_fixture!("sink_changed", :base)
    candidate = DiffFixtureHelper.load_fixture!("sink_changed", :candidate)

    baseline = Semantic.compare(base, candidate)

    Enum.each(1..20, fn _ ->
      noisy_base = shuffle_with_noise(base)
      noisy_candidate = shuffle_with_noise(candidate)

      assert Semantic.compare(noisy_base, noisy_candidate) == baseline
    end)
  end

  defp shuffle_with_noise(artifact) do
    flows =
      artifact
      |> Map.get("flows", [])
      |> Enum.map(fn flow ->
        flow
        |> Map.put("evidence", flow |> Map.get("evidence", []) |> Enum.shuffle())
        |> Map.put("generated_at", "2026-02-08T10:00:00Z")
      end)
      |> Enum.shuffle()

    artifact
    |> Map.put("flows", flows)
    |> Map.put("summary", %{"noise" => :rand.uniform(1000)})
    |> Map.put("errors", [])
  end
end
