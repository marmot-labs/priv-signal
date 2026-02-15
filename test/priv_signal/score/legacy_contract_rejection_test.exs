defmodule PrivSignal.Score.LegacyContractRejectionTest do
  use ExUnit.Case, async: false

  alias PrivSignal.Score.{Engine, Input}

  test "score input loader rejects legacy v1 diff contract" do
    with_tmp_file(fn path ->
      File.write!(path, Jason.encode!(%{version: "v1", changes: []}))

      assert {:error, {:unsupported_diff_version, %{version: "v1"}}} =
               Input.load_diff_json(path)
    end)
  end

  test "score engine rejects legacy runtime payload without events list" do
    assert {:error, {:unsupported_score_input, %{required: "diff.version=v2 with events[]"}}} =
             Engine.run(%{changes: []}, PrivSignal.Config.default_scoring())
  end

  test "score runtime no longer references legacy buckets/rules modules" do
    repo_root = Path.expand("../../..", __DIR__)

    runtime_files = [
      Path.join(repo_root, "lib/priv_signal/score/engine.ex"),
      Path.join(repo_root, "lib/priv_signal/score/input.ex"),
      Path.join(repo_root, "lib/priv_signal/score/output/json.ex"),
      Path.join(repo_root, "lib/mix/tasks/priv_signal.score.ex")
    ]

    runtime_source =
      runtime_files
      |> Enum.map(&File.read!/1)
      |> Enum.join("\n")

    refute String.contains?(runtime_source, "PrivSignal.Score.Buckets")
    refute String.contains?(runtime_source, "PrivSignal.Score.Rules")
    refute String.contains?(runtime_source, "Map.get(diff, :changes")
  end

  defp with_tmp_file(fun) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "priv_signal_score_legacy_reject_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    path = Path.join(dir, "diff.json")
    fun.(path)
  end
end
