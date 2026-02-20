defmodule PrivSignal.Scan.Scanners.TelemetryTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Scan.Scanner.Telemetry
  alias PrivSignal.Validate.AST

  @fixture_root Path.expand("../../../fixtures/sinks", __DIR__)

  test "detects telemetry execute as external sink" do
    inventory = fixture_inventory()
    path = fixture_path("lib/fixtures/telemetry_sink.ex")
    {:ok, ast} = AST.parse_file(path)

    findings =
      Telemetry.scan_ast(ast, %{path: path}, inventory,
        scanner_config: PrivSignal.Config.default_scanners()
      )

    assert length(findings) == 1
    finding = hd(findings)

    assert finding.role_kind == "telemetry"
    assert finding.boundary == "external"
    assert finding.sink == ":telemetry.execute"
    assert Enum.any?(finding.matched_nodes, &(&1.name == "email"))
  end

  defp fixture_inventory do
    {:ok, config} = Loader.load(fixture_path("config/valid_sinks_pii.yml"))
    Inventory.build(config)
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
