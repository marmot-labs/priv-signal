defmodule Mix.Tasks.PrivSignal.DiffV2IntegrationTest do
  use ExUnit.Case

  alias PrivSignal.Test.DiffFixtureHelper

  test "mix priv_signal.diff emits v2 json with events array" do
    tmp_dir = make_tmp_dir("priv_signal_diff_v2_json")

    File.cd!(tmp_dir, fn ->
      init_git_repo!()

      base_artifact =
        DiffFixtureHelper.load_fixture!("sink_changed", :base)
        |> Jason.encode!(pretty: true)

      candidate_artifact =
        DiffFixtureHelper.load_fixture!("sink_changed", :candidate)
        |> Jason.encode!(pretty: true)

      File.write!("priv_signal.lockfile.json", base_artifact)
      git!(["add", "priv_signal.lockfile.json"])
      git!(["commit", "-m", "base"])

      File.write!("priv_signal.lockfile.json", candidate_artifact)

      Mix.shell(Mix.Shell.Process)
      Mix.Task.reenable("priv_signal.diff")

      Mix.Tasks.PrivSignal.Diff.run([
        "--base",
        "HEAD",
        "--format",
        "json",
        "--output",
        "tmp/privacy_diff_v2.json"
      ])

      decoded = "tmp/privacy_diff_v2.json" |> File.read!() |> Jason.decode!()

      assert decoded["version"] == "v2"
      assert is_list(decoded["events"])
      assert is_map(decoded["summary"])
      assert Map.has_key?(decoded["summary"], "events_total")
    end)
  end

  defp make_tmp_dir(prefix) do
    tmp_dir = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    tmp_dir
  end

  defp init_git_repo! do
    git!(["init"])
    git!(["config", "user.email", "priv-signal@example.com"])
    git!(["config", "user.name", "PrivSignal Test"])
  end

  defp git!(args) do
    {output, status} = System.cmd("git", args, stderr_to_stdout: true)

    case status do
      0 -> :ok
      _ -> flunk("git #{Enum.join(args, " ")} failed: #{output}")
    end
  end
end
