defmodule PrivSignal.Scan.LoggingRegressionTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Scan.Logger
  alias PrivSignal.Scan.Runner
  alias PrivSignal.Scan.Scanner.Logging

  @fixture_root Path.expand("../../fixtures/scan", __DIR__)

  test "runner logging results are stable across legacy and scanner-module execution paths" do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))
    source_opts = [root: @fixture_root, paths: ["lib/fixtures"]]

    assert {:ok, legacy_result} =
             Runner.run(config,
               source: source_opts,
               scan_fun: &Logger.scan_file/2,
               timeout: 2_000,
               max_concurrency: 1
             )

    assert {:ok, scanner_result} =
             Runner.run(config,
               source: source_opts,
               scanner_modules: [Logging],
               timeout: 2_000,
               max_concurrency: 1
             )

    assert scanner_result.summary == legacy_result.summary
    assert scanner_result.findings == legacy_result.findings
    assert scanner_result.errors == legacy_result.errors
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
