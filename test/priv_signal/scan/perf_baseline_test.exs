defmodule PrivSignal.Scan.PerfBaselineTest do
  use ExUnit.Case, async: false

  alias PrivSignal.Config.Loader
  alias PrivSignal.Scan.Runner

  @fixture_root Path.expand("../../fixtures/sinks", __DIR__)
  @max_duration_ms 5_000

  test "scan run over sinks fixtures stays within baseline envelope" do
    {:ok, config} = Loader.load(fixture_path("config/valid_sinks_pii.yml"))

    {duration_us, {:ok, result}} =
      :timer.tc(fn ->
        Runner.run(config,
          source: [root: @fixture_root, paths: ["lib/fixtures"]],
          timeout: 2_000,
          max_concurrency: 1
        )
      end)

    duration_ms = div(duration_us, 1_000)

    assert result.summary.files_scanned >= 6
    assert result.summary.errors == 0
    assert duration_ms <= @max_duration_ms
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
