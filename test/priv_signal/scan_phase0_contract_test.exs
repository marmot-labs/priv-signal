defmodule PrivSignal.ScanPhase0ContractTest do
  use ExUnit.Case, async: true

  @fixture_root Path.expand("../fixtures/scan", __DIR__)

  test "phase0 scanner source fixtures exist" do
    assert File.exists?(fixture_path("lib/fixtures/confirmed_pii_logging.ex"))
    assert File.exists?(fixture_path("lib/fixtures/possible_pii_logging.ex"))
    assert File.exists?(fixture_path("lib/fixtures/non_pii_logging.ex"))
  end

  test "phase0 config fixtures exist" do
    assert File.exists?(fixture_path("config/valid_pii.yml"))
    assert File.exists?(fixture_path("config/malformed_pii.yml"))
    assert File.exists?(fixture_path("config/deprecated_pii_modules.yml"))
  end

  test "valid pii config fixture is pii-only" do
    assert {:ok, config} = YamlElixir.read_from_file(fixture_path("config/valid_pii.yml"))

    assert is_list(config["pii"])
    refute Map.has_key?(config, "pii_modules")
  end

  test "deprecated pii_modules fixture fails schema validation with migration guidance" do
    {:ok, config} = YamlElixir.read_from_file(fixture_path("config/deprecated_pii_modules.yml"))

    assert {:error, errors} = PrivSignal.Config.Schema.validate(config)
    assert Enum.any?(errors, &String.contains?(&1, "pii_modules is deprecated"))
  end

  test "scanner json output contract includes required top-level keys" do
    result = %{
      scanner_version: "1",
      summary: %{
        confirmed_count: 0,
        possible_count: 0,
        high_sensitivity_count: 0,
        files_scanned: 0,
        errors: 0
      },
      inventory: %{modules: [], field_count: 0},
      findings: [],
      errors: []
    }

    json = PrivSignal.Scan.Output.JSON.render(result)

    assert Map.has_key?(json, :scanner_version)
    assert Map.has_key?(json, :summary)
    assert Map.has_key?(json, :inventory)
    assert Map.has_key?(json, :findings)
    assert Map.has_key?(json, :errors)
  end

  test "scanner markdown output contract includes required sections" do
    result = %{
      scanner_version: "1",
      summary: %{
        confirmed_count: 0,
        possible_count: 0,
        high_sensitivity_count: 0,
        files_scanned: 0,
        errors: 0
      },
      findings: [],
      errors: []
    }

    markdown = PrivSignal.Scan.Output.Markdown.render(result)

    assert String.contains?(markdown, "PrivSignal PII Scan")
    assert String.contains?(markdown, "Scanner version")
    assert String.contains?(markdown, "No PII-relevant logging findings detected.")
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
