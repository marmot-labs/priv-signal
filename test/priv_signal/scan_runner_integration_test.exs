defmodule PrivSignal.ScanRunnerIntegrationTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Scan.Runner

  @fixture_root Path.expand("../fixtures/scan", __DIR__)

  test "runner scans fixture sources and returns deterministic findings" do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))

    assert {:ok, result} =
             Runner.run(
               config,
               source: [root: @fixture_root, paths: ["lib/fixtures"]],
               timeout: 2_000,
               max_concurrency: 2
             )

    assert result.scanner_version == "1"
    assert result.summary.files_scanned == 3
    assert result.summary.confirmed_count >= 1
    assert result.summary.possible_count >= 1
    assert result.summary.errors == 0
    assert result.inventory.field_count == 2

    assert Enum.any?(result.findings, fn finding ->
             finding.module == "Fixtures.Scan.ConfirmedPIILogging" and
               finding.classification == :confirmed_pii
           end)

    assert Enum.any?(result.findings, fn finding ->
             finding.module == "Fixtures.Scan.PossiblePIILogging" and
               finding.classification == :possible_pii
           end)
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
