defmodule PrivSignal.Scan.TelemetrySinksTest do
  use ExUnit.Case, async: false

  alias PrivSignal.Config.Loader
  alias PrivSignal.Scan.Runner

  @fixture_root Path.expand("../../fixtures/sinks", __DIR__)

  test "emits category and candidate telemetry for phase4 scanners" do
    events = [
      [:priv_signal, :scan, :category, :run],
      [:priv_signal, :scan, :candidate, :emit],
      [:priv_signal, :scan, :run]
    ]

    :telemetry.attach_many(
      "priv_signal-scan-sinks-telemetry",
      events,
      &__MODULE__.handle/4,
      self()
    )

    {:ok, config} = Loader.load(fixture_path("config/valid_sinks_pii.yml"))

    assert {:ok, result} =
             Runner.run(config,
               source: [root: @fixture_root, paths: ["lib/fixtures"]],
               timeout: 2_000,
               max_concurrency: 1
             )

    assert result.summary.files_scanned >= 1

    events = collect_events([])

    category_events =
      Enum.filter(events, fn {event, _m, _md} ->
        event == [:priv_signal, :scan, :category, :run]
      end)

    assert Enum.any?(category_events, fn {_e, _m, md} -> md.category == "http" end)
    assert Enum.any?(category_events, fn {_e, _m, md} -> md.category == "controller" end)
    assert Enum.any?(category_events, fn {_e, _m, md} -> md.category == "telemetry" end)
    assert Enum.any?(category_events, fn {_e, _m, md} -> md.category == "database" end)
    assert Enum.any?(category_events, fn {_e, _m, md} -> md.category == "liveview" end)

    candidate_events =
      Enum.filter(events, fn {event, _m, _md} ->
        event == [:priv_signal, :scan, :candidate, :emit]
      end)

    assert Enum.any?(candidate_events, fn {_e, _m, md} ->
             md.role_kind == "http" and md.node_type == "sink"
           end)

    assert Enum.any?(candidate_events, fn {_e, _m, md} ->
             md.role_kind == "database_read" and md.node_type == "source"
           end)

    assert Enum.any?(candidate_events, fn {_e, _m, md} -> md.role_kind == "telemetry" end)
  after
    :telemetry.detach("priv_signal-scan-sinks-telemetry")
  end

  def handle(event, measurements, metadata, parent) do
    send(parent, {:telemetry, event, measurements, metadata})
  end

  defp collect_events(acc) do
    receive do
      {:telemetry, event, measurements, metadata} ->
        collect_events([{event, measurements, metadata} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
