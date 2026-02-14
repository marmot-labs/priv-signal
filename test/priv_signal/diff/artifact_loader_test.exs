defmodule PrivSignal.Diff.ArtifactLoaderTest do
  use ExUnit.Case

  alias PrivSignal.Diff.ArtifactLoader
  alias PrivSignal.Test.DiffFixtureHelper

  test "loads base from git and candidate from workspace by default" do
    base_json =
      DiffFixtureHelper.build_artifact([
        %{
          "id" => "base_flow",
          "source" => "Demo.User.email",
          "entrypoint" => "DemoWeb.UserController.create/2",
          "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
          "boundary" => "internal"
        }
      ])
      |> Jason.encode!()

    candidate_json =
      DiffFixtureHelper.build_artifact([
        %{
          "id" => "candidate_flow",
          "source" => "Demo.User.phone",
          "entrypoint" => "DemoWeb.UserController.create/2",
          "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
          "boundary" => "internal"
        }
      ])
      |> Jason.encode!()

    git_runner = fn "git", ["show", "origin/main:priv_signal.lockfile.json"], _opts ->
      send(self(), :git_base_called)
      {base_json, 0}
    end

    file_reader = fn "priv_signal.lockfile.json" ->
      send(self(), :workspace_candidate_called)
      {:ok, candidate_json}
    end

    options = %{
      base: "origin/main",
      candidate_ref: nil,
      candidate_path: "priv_signal.lockfile.json",
      artifact_path: "priv_signal.lockfile.json",
      strict?: false
    }

    assert {:ok, loaded} =
             ArtifactLoader.load(options, git_runner: git_runner, file_reader: file_reader)

    assert received?(:git_base_called)
    assert received?(:workspace_candidate_called)
    assert loaded.metadata.base_ref == "origin/main"
    assert loaded.metadata.candidate_source.type == :workspace
  end

  test "loads both base and candidate from git in candidate-ref mode" do
    json =
      DiffFixtureHelper.build_artifact([
        %{
          "id" => "flow_1",
          "source" => "Demo.User.email",
          "entrypoint" => "DemoWeb.UserController.create/2",
          "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
          "boundary" => "internal"
        }
      ])
      |> Jason.encode!()

    git_runner = fn
      "git", ["show", "origin/main:priv_signal.lockfile.json"], _opts ->
        send(self(), :git_base_called)
        {json, 0}

      "git", ["show", "HEAD:priv_signal.lockfile.json"], _opts ->
        send(self(), :git_candidate_called)
        {json, 0}
    end

    file_reader = fn _path ->
      flunk("workspace reader should not be called in candidate-ref mode")
    end

    options = %{
      base: "origin/main",
      candidate_ref: "HEAD",
      candidate_path: nil,
      artifact_path: "priv_signal.lockfile.json",
      strict?: false
    }

    assert {:ok, loaded} =
             ArtifactLoader.load(options, git_runner: git_runner, file_reader: file_reader)

    assert received?(:git_base_called)
    assert received?(:git_candidate_called)
    assert loaded.metadata.candidate_source.type == :git_ref
    assert loaded.metadata.candidate_source.ref == "HEAD"
  end

  test "integration: loads base from git and candidate from workspace" do
    tmp_dir = make_tmp_dir("priv_signal_diff_loader_success")

    File.cd!(tmp_dir, fn ->
      init_git_repo!()

      base_artifact =
        DiffFixtureHelper.build_artifact([
          %{
            "id" => "flow_base",
            "source" => "Demo.User.email",
            "entrypoint" => "DemoWeb.UserController.create/2",
            "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
            "boundary" => "internal"
          }
        ])
        |> Jason.encode!(pretty: true)

      File.write!("priv_signal.lockfile.json", base_artifact)
      git!(["add", "priv_signal.lockfile.json"])
      git!(["commit", "-m", "base lockfile"])

      candidate_artifact =
        DiffFixtureHelper.build_artifact([
          %{
            "id" => "flow_candidate",
            "source" => "Demo.User.phone",
            "entrypoint" => "DemoWeb.UserController.create/2",
            "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
            "boundary" => "internal"
          }
        ])
        |> Jason.encode!(pretty: true)

      File.write!("priv_signal.lockfile.json", candidate_artifact)

      options = %{
        base: "HEAD",
        candidate_ref: nil,
        candidate_path: "priv_signal.lockfile.json",
        artifact_path: "priv_signal.lockfile.json",
        strict?: false
      }

      assert {:ok, loaded} = ArtifactLoader.load(options)
      assert Enum.any?(loaded.base["flows"], &(&1["id"] == "flow_base"))
      assert Enum.any?(loaded.candidate["flows"], &(&1["id"] == "flow_candidate"))
    end)
  end

  test "integration: returns git failure for invalid base ref" do
    tmp_dir = make_tmp_dir("priv_signal_diff_loader_failure")

    File.cd!(tmp_dir, fn ->
      init_git_repo!()

      artifact =
        DiffFixtureHelper.build_artifact([
          %{
            "id" => "flow_1",
            "source" => "Demo.User.email",
            "entrypoint" => "DemoWeb.UserController.create/2",
            "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
            "boundary" => "internal"
          }
        ])
        |> Jason.encode!(pretty: true)

      File.write!("priv_signal.lockfile.json", artifact)
      git!(["add", "priv_signal.lockfile.json"])
      git!(["commit", "-m", "base lockfile"])

      options = %{
        base: "missing-ref",
        candidate_ref: nil,
        candidate_path: "priv_signal.lockfile.json",
        artifact_path: "priv_signal.lockfile.json",
        strict?: false
      }

      assert {:error, {:base_git_show_failed, %{base_ref: "missing-ref"}}} =
               ArtifactLoader.load(options)
    end)
  end

  test "returns candidate artifact not found when workspace file is missing" do
    git_runner = fn "git", ["show", "origin/main:priv_signal.lockfile.json"], _opts ->
      json =
        DiffFixtureHelper.build_artifact([
          %{
            "id" => "flow_1",
            "source" => "Demo.User.email",
            "entrypoint" => "DemoWeb.UserController.create/2",
            "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
            "boundary" => "internal"
          }
        ])
        |> Jason.encode!()

      {json, 0}
    end

    file_reader = fn _path -> {:error, :enoent} end

    options = %{
      base: "origin/main",
      candidate_ref: nil,
      candidate_path: "missing.json",
      artifact_path: "priv_signal.lockfile.json",
      strict?: false
    }

    assert {:error, {:candidate_artifact_not_found, %{path: "missing.json", source: :workspace}}} =
             ArtifactLoader.load(options, git_runner: git_runner, file_reader: file_reader)
  end

  test "strict mode surfaces missing optional sections as contract failure" do
    minimal_artifact_json =
      Jason.encode!(%{
        "schema_version" => "1.2",
        "flows" => [
          %{
            "id" => "flow_1",
            "source" => "Demo.User.email",
            "entrypoint" => "DemoWeb.UserController.create/2",
            "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
            "boundary" => "internal"
          }
        ]
      })

    git_runner = fn "git", ["show", "origin/main:priv_signal.lockfile.json"], _opts ->
      {minimal_artifact_json, 0}
    end

    file_reader = fn "priv_signal.lockfile.json" -> {:ok, minimal_artifact_json} end

    options = %{
      base: "origin/main",
      candidate_ref: nil,
      candidate_path: "priv_signal.lockfile.json",
      artifact_path: "priv_signal.lockfile.json",
      strict?: true
    }

    assert {:error, {:base_artifact_contract_failed, %{reason: {:missing_optional_sections, _}}}} =
             ArtifactLoader.load(options, git_runner: git_runner, file_reader: file_reader)
  end

  defp received?(message) do
    receive do
      ^message -> true
    after
      0 -> false
    end
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
