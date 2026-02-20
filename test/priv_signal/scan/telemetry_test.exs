defmodule PrivSignal.Scan.TelemetryTest do
  use ExUnit.Case, async: false

  alias PrivSignal.Config.Loader
  alias PrivSignal.Scan.Output.{JSON, Writer}
  alias PrivSignal.Scan.Runner

  @fixture_root Path.expand("../../fixtures/scan", __DIR__)

  test "emits scan inventory/run/output telemetry events with cardinality-safe metadata" do
    events = [
      [:priv_signal, :scan, :inventory, :build],
      [:priv_signal, :scan, :run],
      [:priv_signal, :scan, :output, :write]
    ]

    :telemetry.attach_many("priv_signal-scan-test", events, &__MODULE__.handle_event/4, self())

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
        "priv_signal_scan_telemetry_#{System.unique_integer([:positive])}.json"
      )

    assert {:ok, _} = Writer.write("scan markdown", json, quiet: true, json_path: out)

    assert_received {:telemetry, [:priv_signal, :scan, :inventory, :build], measurements1,
                     metadata1}

    assert measurements1.duration_ms >= 0
    assert is_integer(metadata1.module_count)
    assert is_integer(metadata1.node_count)

    assert_received {:telemetry, [:priv_signal, :scan, :run], measurements2, metadata2}
    assert measurements2.file_count >= 1
    assert measurements2.finding_count >= 1
    assert is_boolean(metadata2.ok)
    assert is_boolean(metadata2.strict_mode)
    assert metadata2.scanner_version == "1"
    refute Map.has_key?(metadata2, :file)
    refute Map.has_key?(metadata2, :path)
    refute Map.has_key?(metadata2, :field_name)

    assert_received {:telemetry, [:priv_signal, :scan, :output, :write], measurements3, metadata3}
    assert measurements3.duration_ms >= 0
    assert metadata3.ok == true
    assert metadata3.format == :json
    assert metadata3.scanner_version == "1"
    refute Map.has_key?(metadata3, :path)
  after
    :telemetry.detach("priv_signal-scan-test")
  end

  def handle_event(event, measurements, metadata, parent) do
    send(parent, {:telemetry, event, measurements, metadata})
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
