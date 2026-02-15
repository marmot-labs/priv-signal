defmodule PrivSignal.Scan.Scanners.DatabaseTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Scan.Scanner.Database
  alias PrivSignal.Validate.AST

  @fixture_root Path.expand("../../../fixtures/sinks", __DIR__)

  test "detects repo reads and writes" do
    inventory = fixture_inventory()
    path = fixture_path("lib/fixtures/database_access.ex")
    {:ok, ast} = AST.parse_file(path)

    findings =
      Database.scan_ast(ast, %{path: path}, inventory,
        scanner_config: PrivSignal.Config.default_scanners()
      )

    assert length(findings) == 2
    assert Enum.any?(findings, &(&1.role_kind == "database_read" and &1.sink == "Repo.get"))
    assert Enum.any?(findings, &(&1.role_kind == "database_write" and &1.sink == "Repo.insert"))
  end

  defp fixture_inventory do
    {:ok, config} = Loader.load(fixture_path("config/valid_sinks_pii.yml"))
    Inventory.build(config)
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
