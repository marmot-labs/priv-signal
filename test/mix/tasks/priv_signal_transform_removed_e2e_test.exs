defmodule Mix.Tasks.PrivSignal.TransformRemovedE2ETest do
  use ExUnit.Case

  alias PrivSignal.Test.DiffFixtureHelper

  test "fixture pair reaches transform_removed high rule through diff -> score" do
    tmp_dir = make_tmp_dir("priv_signal_transform_removed_e2e")

    File.cd!(tmp_dir, fn ->
      init_git_repo!()
      write_valid_config()

      base_artifact =
        DiffFixtureHelper.load_fixture!("transform_removed_high", :base)
        |> Jason.encode!(pretty: true)

      candidate_artifact =
        DiffFixtureHelper.load_fixture!("transform_removed_high", :candidate)
        |> Jason.encode!(pretty: true)

      File.write!("priv_signal.lockfile.json", base_artifact)
      git!(["add", "priv_signal.yml", "priv_signal.lockfile.json"])
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

      diff_payload = File.read!("tmp/privacy_diff_v2.json") |> Jason.decode!()

      assert Enum.any?(diff_payload["events"], fn event ->
               event["event_type"] == "transform_changed" and
                 "Demo.User.accommodation_status" in (get_in(event, ["transform_delta", "removed"]) || [])
             end)

      Mix.Task.reenable("priv_signal.score")

      Mix.Tasks.PrivSignal.Score.run([
        "--diff",
        "tmp/privacy_diff_v2.json",
        "--output",
        "tmp/priv_signal_score_v2.json",
        "--quiet"
      ])

      score_payload = File.read!("tmp/priv_signal_score_v2.json") |> Jason.decode!()

      assert score_payload["score"] == "HIGH"
      assert get_in(score_payload, ["summary", "events_high"]) == 1
    end)
  end

  defp write_valid_config do
    File.write!(
      "priv_signal.yml",
      """
      version: 1

      prd_nodes:
        - key: demo_user_user_id
          label: Demo User ID
          class: persistent_pseudonymous_identifier
          sensitive: false
          scope:
            module: Demo.User
            field: user_id
      """
    )
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
