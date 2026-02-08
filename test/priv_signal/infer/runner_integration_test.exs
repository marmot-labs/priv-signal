defmodule PrivSignal.Infer.RunnerIntegrationTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Infer.Runner

  @fixture_root Path.expand("../../fixtures/scan", __DIR__)

  test "runner emits deterministic infer inventory from scan fixtures" do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))

    assert {:ok, first} =
             Runner.run(config,
               source: [root: @fixture_root, paths: ["lib/fixtures"]],
               timeout: 2_000,
               max_concurrency: 2
             )

    assert {:ok, second} =
             Runner.run(config,
               source: [root: @fixture_root, paths: ["lib/fixtures"]],
               timeout: 2_000,
               max_concurrency: 2
             )

    assert first.schema_version == "1.2"
    assert first.summary.files_scanned == 3
    assert first.summary.node_count >= 2
    assert first.summary.flow_count >= 2
    assert is_binary(first.summary.flows_hash)
    assert first.summary.proto_flows_enabled == true
    assert first.summary.scan_error_count == 0
    assert is_list(first.nodes)
    assert is_list(first.flows)
    assert Enum.all?(first.nodes, &(&1.node_type == "sink"))
    assert Enum.all?(first.flows, &String.starts_with?(&1.id, "psf_"))
    assert Enum.all?(first.flows, &is_list(&1.evidence))

    assert first.nodes == second.nodes
    assert first.flows == second.flows
    assert first.summary == second.summary
  end

  test "runner disables proto flows when feature flag is off" do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))
    System.put_env("PRIV_SIGNAL_INFER_PROTO_FLOWS_V1", "false")

    try do
      assert {:ok, result} =
               Runner.run(config,
                 source: [root: @fixture_root, paths: ["lib/fixtures"]],
                 timeout: 2_000,
                 max_concurrency: 2
               )

      assert result.summary.proto_flows_enabled == false
      assert result.summary.flow_count == 0
      assert result.summary.flow_candidate_count == 0
      assert result.flows == []
    after
      System.delete_env("PRIV_SIGNAL_INFER_PROTO_FLOWS_V1")
    end
  end

  test "runner can emit standalone entrypoint nodes when feature toggle enabled" do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))
    tmp_root = make_tmp_project_with_worker_logging()

    System.put_env("PRIV_SIGNAL_INFER_EMIT_ENTRYPOINT_NODES", "true")

    try do
      assert {:ok, result} =
               Runner.run(config,
                 source: [root: tmp_root, paths: ["lib"]],
                 timeout: 2_000,
                 max_concurrency: 2
               )

      assert Enum.any?(result.nodes, &(&1.node_type == "entrypoint"))
      assert Enum.any?(result.nodes, &(&1.node_type == "sink"))
    after
      System.delete_env("PRIV_SIGNAL_INFER_EMIT_ENTRYPOINT_NODES")
      File.rm_rf!(tmp_root)
    end
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)

  defp make_tmp_project_with_worker_logging do
    root =
      Path.join(
        System.tmp_dir!(),
        "priv_signal_infer_runner_#{System.unique_integer([:positive])}"
      )

    file_path = Path.join(root, "lib/my_app/workers/export_worker.ex")
    File.mkdir_p!(Path.dirname(file_path))

    File.write!(
      file_path,
      """
      defmodule MyApp.Workers.ExportWorker do
        require Logger

        def perform(user) do
          Logger.info("export user", email: user.email)
        end
      end
      """
    )

    root
  end
end
