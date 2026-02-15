defmodule PrivSignal.Scan.ScannerTest.NoopA do
  @behaviour PrivSignal.Scan.Scanner

  @impl true
  def scan_ast(_ast, _file_ctx, _inventory, _opts), do: []
end

defmodule PrivSignal.Scan.ScannerTest.NoopB do
  @behaviour PrivSignal.Scan.Scanner

  @impl true
  def scan_ast(_ast, _file_ctx, _inventory, _opts), do: []
end

defmodule PrivSignal.Scan.RunnerSingleParseTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Scan.Runner
  alias PrivSignal.Validate.AST

  @fixture_root Path.expand("../../fixtures/scan", __DIR__)

  test "runner parses each file once even with multiple scanners" do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    parse_fun = fn file ->
      Agent.update(counter, &(&1 + 1))
      AST.parse_file(file)
    end

    assert {:ok, result} =
             Runner.run(config,
               source: [root: @fixture_root, paths: ["lib/fixtures"]],
               scanner_modules: [
                 PrivSignal.Scan.ScannerTest.NoopA,
                 PrivSignal.Scan.ScannerTest.NoopB
               ],
               parse_fun: parse_fun,
               timeout: 2_000,
               max_concurrency: 1
             )

    assert result.summary.files_scanned == 3
    assert result.findings == []
    assert Agent.get(counter, & &1) == result.summary.files_scanned
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
