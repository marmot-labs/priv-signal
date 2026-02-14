defmodule PrivSignal.Diff.RunnerTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Diff.Runner
  alias PrivSignal.Test.DiffFixtureHelper

  test "returns full report payload with human and json outputs" do
    base = DiffFixtureHelper.load_fixture!("flow_added", :base) |> Jason.encode!()
    candidate = DiffFixtureHelper.load_fixture!("flow_added", :candidate) |> Jason.encode!()

    git_runner = fn "git", ["show", "origin/main:priv_signal.lockfile.json"], _opts ->
      {base, 0}
    end

    file_reader = fn "priv_signal.lockfile.json" -> {:ok, candidate} end

    options = %{
      base: "origin/main",
      candidate_ref: nil,
      candidate_path: "priv_signal.lockfile.json",
      artifact_path: "priv_signal.lockfile.json",
      include_confidence?: false,
      strict?: false,
      format: :human
    }

    assert {:ok, result} = Runner.run(options, git_runner: git_runner, file_reader: file_reader)

    assert is_binary(result.human)
    assert result.json.summary.total == 1
    assert result.json.summary.high == 1
    assert result.report.metadata.base_ref == "origin/main"
  end

  test "returns error from loader unchanged for actionable handling" do
    options = %{
      base: "missing-ref",
      candidate_ref: nil,
      candidate_path: "priv_signal.lockfile.json",
      artifact_path: "priv_signal.lockfile.json",
      include_confidence?: false,
      strict?: false,
      format: :human
    }

    assert {:error, {:base_git_show_failed, %{base_ref: "missing-ref"}}} = Runner.run(options)
  end

  test "supports optional confidence change comparisons in orchestrated pipeline" do
    base =
      DiffFixtureHelper.build_artifact([
        %{
          "id" => "flow_1",
          "source" => "Demo.User.email",
          "entrypoint" => "DemoWeb.UserController.create/2",
          "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
          "boundary" => "internal",
          "confidence" => 0.1,
          "evidence" => ["node_a"]
        }
      ])
      |> Jason.encode!()

    candidate =
      DiffFixtureHelper.build_artifact([
        %{
          "id" => "flow_1",
          "source" => "Demo.User.email",
          "entrypoint" => "DemoWeb.UserController.create/2",
          "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
          "boundary" => "internal",
          "confidence" => 0.9,
          "evidence" => ["node_a"]
        }
      ])
      |> Jason.encode!()

    git_runner = fn "git", ["show", "origin/main:priv_signal.lockfile.json"], _opts ->
      {base, 0}
    end

    file_reader = fn "priv_signal.lockfile.json" -> {:ok, candidate} end

    options = %{
      base: "origin/main",
      candidate_ref: nil,
      candidate_path: "priv_signal.lockfile.json",
      artifact_path: "priv_signal.lockfile.json",
      include_confidence?: true,
      strict?: false,
      format: :json
    }

    assert {:ok, result} = Runner.run(options, git_runner: git_runner, file_reader: file_reader)

    assert Enum.any?(result.json.changes, &(&1.type == "confidence_changed"))
    assert Enum.any?(result.json.changes, &(&1.rule_id == "R-LOW-CONFIDENCE-ONLY"))
  end
end
