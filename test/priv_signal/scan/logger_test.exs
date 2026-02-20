defmodule PrivSignal.Scan.LoggerTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Scan.Logger

  @fixture_root Path.expand("../../fixtures/scan", __DIR__)

  test "detects Logger.<level> sink and direct pii field evidence" do
    inventory = fixture_inventory()
    path = fixture_path("lib/fixtures/confirmed_pii_logging.ex")

    assert {:ok, findings} = Logger.scan_file(path, inventory)
    assert length(findings) == 1

    finding = hd(findings)

    assert finding.module == "Fixtures.Scan.ConfirmedPIILogging"
    assert finding.function == "log_user_email"
    assert finding.arity == 1
    assert finding.file == path
    assert finding.sink == "Logger.info"
    assert finding.line == 5
    assert Enum.any?(finding.evidence, &(&1.type == :direct_field_access))
    assert Enum.any?(finding.matched_nodes, &(&1.name == "email"))
  end

  test "detects possible bulk inspect logging pattern" do
    inventory = fixture_inventory()
    path = fixture_path("lib/fixtures/possible_pii_logging.ex")

    assert {:ok, findings} = Logger.scan_file(path, inventory)
    assert length(findings) == 1
    assert hd(findings).sink == "Logger.debug"
    assert Enum.any?(hd(findings).evidence, &(&1.type == :bulk_inspect))
  end

  test "detects :logger sink calls" do
    inventory = fixture_inventory()

    path =
      write_tmp_source("""
      defmodule Fixtures.Scan.ErlangLogger do
        def emit(user) do
          :logger.info(%{email: user.email})
        end
      end
      """)

    assert {:ok, findings} = Logger.scan_file(path, inventory)
    assert length(findings) == 1
    assert hd(findings).sink == ":logger.info"
    assert Enum.any?(hd(findings).matched_nodes, &(&1.name == "email"))
  end

  defp fixture_inventory do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))
    Inventory.build(config)
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)

  defp write_tmp_source(source) do
    path =
      Path.join(
        System.tmp_dir!(),
        "priv_signal_scan_logger_test_#{System.unique_integer([:positive])}.ex"
      )

    File.write!(path, source)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
