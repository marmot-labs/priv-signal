defmodule PrivSignal.Infer.TelemetryTest do
  use ExUnit.Case, async: false

  alias PrivSignal.Config.Loader
  alias PrivSignal.Infer.Output.{JSON, Writer}
  alias PrivSignal.Infer.Runner

  @fixture_root Path.expand("../../fixtures/scan", __DIR__)

  test "emits infer run/flow/output telemetry events with safe metadata" do
    events = [
      [:priv_signal, :infer, :run, :start],
      [:priv_signal, :infer, :flow, :build],
      [:priv_signal, :infer, :run, :stop],
      [:priv_signal, :infer, :output, :write]
    ]

    :telemetry.attach_many("priv_signal-infer-test", events, &__MODULE__.handle_event/4, self())

    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))

    assert {:ok, result} =
             Runner.run(config,
               source: [root: @fixture_root, paths: ["lib/fixtures"]],
               max_concurrency: 2,
               timeout: 2_000
             )

    json = JSON.render(result)

    out =
      Path.join(
        System.tmp_dir!(),
        "priv_signal_infer_telemetry_#{System.unique_integer([:positive])}.json"
      )

    assert {:ok, _} = Writer.write("infer markdown", json, quiet: true, json_path: out)

    assert_received {:telemetry, [:priv_signal, :infer, :run, :start], _m1, metadata1}
    assert is_boolean(metadata1.strict_mode)
    assert is_boolean(metadata1.proto_flows_enabled)

    assert_received {:telemetry, [:priv_signal, :infer, :flow, :build], measurements2, metadata2}
    assert measurements2.duration_ms >= 0
    assert measurements2.node_count >= 1
    assert measurements2.flow_count >= 1
    assert is_list(metadata2.entrypoint_kinds_present)
    assert is_map(metadata2.boundary_counts)
    assert is_boolean(metadata2.proto_flows_enabled)
    refute Map.has_key?(metadata2, :flow_id)
    refute Map.has_key?(metadata2, :node_id)

    assert_received {:telemetry, [:priv_signal, :infer, :run, :stop], measurements3, metadata3}
    assert measurements3.duration_ms >= 0
    assert measurements3.node_count >= 1
    assert measurements3.flow_count >= 1
    assert is_boolean(metadata3.ok)
    assert is_boolean(metadata3.strict_mode)
    assert is_boolean(metadata3.proto_flows_enabled)
    assert metadata3.schema_version == "1.2"
    assert metadata3.determinism_hash_changed == 0

    assert_received {:telemetry, [:priv_signal, :infer, :output, :write], measurements4,
                     metadata4}

    assert measurements4.duration_ms >= 0
    assert metadata4.ok == true
    assert metadata4.format == :json
    assert metadata4.schema_version == "1.2"
  after
    :telemetry.detach("priv_signal-infer-test")
  end

  def handle_event(event, measurements, metadata, parent) do
    send(parent, {:telemetry, event, measurements, metadata})
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
