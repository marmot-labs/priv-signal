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

  test "detects wrapper-based DB writes through intra-module summaries" do
    inventory = fixture_inventory()

    path =
      write_tmp_source("""
      defmodule Fixtures.DatabaseWrapper do
        alias MyApp.Repo

        def persist(user), do: append_step(%{email: user.email})

        def append_step(attrs) do
          Repo.insert(attrs)
        end
      end
      """)

    {:ok, ast} = AST.parse_file(path)

    scanners = PrivSignal.Config.default_scanners()
    scanners = put_in(scanners.database.repo_modules, ["MyApp.Repo"])
    scanners = put_in(scanners.database.wrapper_modules, ["Fixtures.DatabaseWrapper"])
    scanners = put_in(scanners.database.wrapper_functions, ["append_step/1"])

    findings = Database.scan_ast(ast, %{path: path}, inventory, scanner_config: scanners)

    assert Enum.any?(findings, &(&1.role_kind == "database_write" and &1.sink == "Repo.insert"))

    assert Enum.any?(findings, fn finding ->
             finding.role_kind == "database_write" and
               finding.sink == "Wrapper.Fixtures.DatabaseWrapper.append_step/1" and
               finding.role_subtype == "wrapper" and
               Enum.any?(finding.evidence, &(&1.type == :inherited_db_wrapper))
           end)
  end

  defp fixture_inventory do
    {:ok, config} = Loader.load(fixture_path("config/valid_sinks_pii.yml"))
    Inventory.build(config)
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)

  defp write_tmp_source(source) do
    path =
      Path.join(
        System.tmp_dir!(),
        "priv_signal_db_scanner_#{System.unique_integer([:positive])}.ex"
      )

    File.write!(path, source)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
