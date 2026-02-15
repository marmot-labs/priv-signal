defmodule Mix.Tasks.PrivSignalV2E2ETest do
  use ExUnit.Case

  test "scan -> diff(v2) -> score(v2) pipeline succeeds" do
    tmp_dir = make_tmp_dir("priv_signal_v2_e2e")

    File.cd!(tmp_dir, fn ->
      init_git_repo!()
      write_valid_config()

      write_source("""
      defmodule Demo.Logger do
        def run(_user) do
          :ok
        end
      end
      """)

      Mix.shell(Mix.Shell.Process)

      Mix.Task.reenable("priv_signal.scan")
      Mix.Tasks.PrivSignal.Scan.run(["--quiet"])
      assert File.exists?("priv_signal.lockfile.json")

      git!(["add", "priv-signal.yml", "lib/demo_logger.ex", "priv_signal.lockfile.json"])
      git!(["commit", "-m", "base"])

      write_source("""
      defmodule Demo.Logger do
        require Logger

        def run(user) do
          Logger.info("email=\#{user.email}")
        end
      end
      """)

      Mix.Task.reenable("priv_signal.scan")
      Mix.Tasks.PrivSignal.Scan.run(["--quiet"])
      assert File.exists?("priv_signal.lockfile.json")

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
      assert diff_payload["version"] == "v2"
      assert is_list(diff_payload["events"])

      Mix.Task.reenable("priv_signal.score")

      Mix.Tasks.PrivSignal.Score.run([
        "--diff",
        "tmp/privacy_diff_v2.json",
        "--output",
        "tmp/priv_signal_score_v2.json",
        "--quiet"
      ])

      score_payload = File.read!("tmp/priv_signal_score_v2.json") |> Jason.decode!()
      assert score_payload["version"] == "v2"
      assert score_payload["score"] in ["NONE", "LOW", "MEDIUM", "HIGH"]
      refute Map.has_key?(score_payload, "points")
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

  defp write_valid_config do
    File.write!(
      "priv-signal.yml",
      """
      version: 1

      pii:
        - module: Demo.User
          fields:
            - name: email
              category: contact
              sensitivity: high

      flows: []
      """
    )
  end

  defp write_source(contents) do
    File.mkdir_p!("lib")
    File.write!("lib/demo_logger.ex", contents)
  end

  defp git!(args) do
    {output, status} = System.cmd("git", args, stderr_to_stdout: true)

    case status do
      0 -> :ok
      _ -> flunk("git #{Enum.join(args, " ")} failed: #{output}")
    end
  end
end
