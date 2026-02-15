defmodule PrivSignal.Scan.Scanners.OverridesTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Scan.Scanner.Controller
  alias PrivSignal.Scan.Scanner.HTTP
  alias PrivSignal.Scan.Scanner.Logging
  alias PrivSignal.Scan.Scanner.Telemetry
  alias PrivSignal.Validate.AST

  @fixture_root Path.expand("../../../fixtures/sinks", __DIR__)

  test "http additional_modules override enables custom wrapper detection" do
    inventory = fixture_inventory()

    path =
      write_tmp_source("""
      defmodule Fixtures.CustomHTTP do
        def call(user) do
          MyApp.HTTP.request("https://api.segment.io/v1/track", %{email: user.email})
        end
      end
      """)

    {:ok, ast} = AST.parse_file(path)

    scanners = PrivSignal.Config.default_scanners()
    scanners = put_in(scanners.http.additional_modules, ["MyApp.HTTP"])

    findings = HTTP.scan_ast(ast, %{path: path}, inventory, scanner_config: scanners)

    assert length(findings) == 1
    assert hd(findings).sink == "MyApp.HTTP.request"
  end

  test "telemetry additional_modules override enables custom analytics detection" do
    inventory = fixture_inventory()

    path =
      write_tmp_source("""
      defmodule Fixtures.CustomTelemetry do
        def track(user) do
          MyApp.Analytics.capture(%{email: user.email})
        end
      end
      """)

    {:ok, ast} = AST.parse_file(path)

    scanners = PrivSignal.Config.default_scanners()
    scanners = put_in(scanners.telemetry.additional_modules, ["MyApp.Analytics"])

    findings = Telemetry.scan_ast(ast, %{path: path}, inventory, scanner_config: scanners)

    assert length(findings) == 1
    assert hd(findings).sink == "MyApp.Analytics.capture"
  end

  test "controller additional_render_functions override enables custom render detection" do
    inventory = fixture_inventory()

    path =
      write_tmp_source("""
      defmodule Fixtures.CustomController do
        def show(conn, user) do
          MyAppWeb.API.render_json(conn, %{email: user.email})
        end
      end
      """)

    {:ok, ast} = AST.parse_file(path)

    scanners = PrivSignal.Config.default_scanners()

    scanners =
      put_in(scanners.controller.additional_render_functions, ["MyAppWeb.API.render_json"])

    findings = Controller.scan_ast(ast, %{path: path}, inventory, scanner_config: scanners)

    assert length(findings) == 1
    assert hd(findings).sink == "MyAppWeb.API.render_json"
  end

  test "logging additional_modules override enables custom logging wrapper detection" do
    inventory = fixture_inventory()

    path =
      write_tmp_source("""
      defmodule Fixtures.CustomLogging do
        def log(user) do
          MyApp.Logging.info(%{email: user.email})
        end
      end
      """)

    {:ok, ast} = AST.parse_file(path)

    scanners = PrivSignal.Config.default_scanners()
    scanners = put_in(scanners.logging.additional_modules, ["MyApp.Logging"])

    findings = Logging.scan_ast(ast, %{path: path}, inventory, scanner_config: scanners)

    assert length(findings) == 1
    assert hd(findings).sink == "MyApp.Logging.info"
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
        "priv_signal_scanner_overrides_#{System.unique_integer([:positive])}.ex"
      )

    File.write!(path, source)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
