defmodule PrivSignal.Scan.ScannerBehaviorTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Scan.Scanner
  alias PrivSignal.Scan.Scanner.Logging
  alias PrivSignal.Validate.AST

  @fixture_root Path.expand("../../fixtures/scan", __DIR__)

  test "logging scanner implements scanner behavior contract" do
    assert Scanner.valid_module?(Logging)
  end

  test "logging scanner scan_ast returns deterministic candidate list" do
    inventory = fixture_inventory()
    path = fixture_path("lib/fixtures/confirmed_pii_logging.ex")
    {:ok, ast} = AST.parse_file(path)

    candidates_a = Logging.scan_ast(ast, %{path: path}, inventory, [])
    candidates_b = Logging.scan_ast(ast, %{path: path}, inventory, [])

    assert is_list(candidates_a)
    assert candidates_a == candidates_b

    assert Enum.any?(candidates_a, fn candidate ->
             candidate.module == "Fixtures.Scan.ConfirmedPIILogging" and
               candidate.sink == "Logger.info"
           end)
  end

  defp fixture_inventory do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))
    Inventory.build(config)
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
