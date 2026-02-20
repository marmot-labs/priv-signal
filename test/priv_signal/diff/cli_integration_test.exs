defmodule PrivSignal.Diff.CLIIntegrationTest do
  use ExUnit.Case

  alias PrivSignal.Test.DiffFixtureHelper

  test "mix priv_signal.diff succeeds in workspace-candidate mode without priv_signal.yml" do
    tmp_dir = make_tmp_dir("priv_signal_diff_cli_workspace")

    File.cd!(tmp_dir, fn ->
      init_git_repo!()

      base_artifact =
        DiffFixtureHelper.load_fixture!("flow_added", :base)
        |> Jason.encode!(pretty: true)

      candidate_artifact =
        DiffFixtureHelper.load_fixture!("flow_added", :candidate)
        |> Jason.encode!(pretty: true)

      File.write!("priv_signal.lockfile.json", base_artifact)
      git!(["add", "priv_signal.lockfile.json"])
      git!(["commit", "-m", "base"])

      File.write!("priv_signal.lockfile.json", candidate_artifact)

      Mix.shell(Mix.Shell.Process)
      Mix.Task.reenable("priv_signal.diff")
      Mix.Tasks.PrivSignal.Diff.run(["--base", "HEAD"])

      assert_received {:mix_shell, :info, [message]}
      assert String.contains?(message, "Privacy-Relevant Changes Detected")
      refute File.exists?("priv_signal.yml")
    end)
  end

  test "mix priv_signal.diff writes json output when requested" do
    tmp_dir = make_tmp_dir("priv_signal_diff_cli_json")

    File.cd!(tmp_dir, fn ->
      init_git_repo!()

      base_artifact =
        DiffFixtureHelper.load_fixture!("no_change", :base)
        |> Jason.encode!(pretty: true)

      File.write!("priv_signal.lockfile.json", base_artifact)
      git!(["add", "priv_signal.lockfile.json"])
      git!(["commit", "-m", "base"])

      Mix.shell(Mix.Shell.Process)
      Mix.Task.reenable("priv_signal.diff")

      Mix.Tasks.PrivSignal.Diff.run([
        "--base",
        "HEAD",
        "--format",
        "json",
        "--output",
        "tmp/semantic-diff.json"
      ])

      assert File.exists?("tmp/semantic-diff.json")
      decoded = "tmp/semantic-diff.json" |> File.read!() |> Jason.decode!()
      assert decoded["version"] == "v2"
      assert is_map(decoded["summary"])
      assert is_list(decoded["events"])
    end)
  end

  test "mix priv_signal.diff fails with actionable message for invalid base ref" do
    tmp_dir = make_tmp_dir("priv_signal_diff_cli_invalid_ref")

    File.cd!(tmp_dir, fn ->
      init_git_repo!()

      artifact =
        DiffFixtureHelper.load_fixture!("no_change", :base)
        |> Jason.encode!(pretty: true)

      File.write!("priv_signal.lockfile.json", artifact)
      git!(["add", "priv_signal.lockfile.json"])
      git!(["commit", "-m", "base"])

      Mix.shell(Mix.Shell.Process)
      Mix.Task.reenable("priv_signal.diff")

      assert_raise Mix.Error, ~r/diff failed/, fn ->
        Mix.Tasks.PrivSignal.Diff.run(["--base", "missing-ref"])
      end

      assert_received {:mix_shell, :error, [message]}
      assert String.contains?(message, "failed reading base ref missing-ref")
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
