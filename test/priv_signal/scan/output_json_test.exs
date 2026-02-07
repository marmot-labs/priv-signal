defmodule PrivSignal.Scan.Output.JSONTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Scan.Evidence
  alias PrivSignal.Scan.Finding
  alias PrivSignal.Scan.Output.JSON

  test "renders scanner result map with expected keys" do
    finding = %Finding{
      id: "abc123",
      classification: :confirmed_pii,
      confidence: :confirmed,
      sensitivity: :high,
      module: "MyApp.Auth",
      function: "login",
      arity: 2,
      file: "lib/my_app/auth.ex",
      line: 84,
      sink: "Logger.info",
      matched_fields: [
        %{module: "MyApp.User", name: "email", category: "contact", sensitivity: "high"}
      ],
      evidence: [
        %Evidence{
          type: :direct_field_access,
          expression: "user.email",
          fields: [%{module: "MyApp.User", name: "email", sensitivity: "high"}]
        }
      ]
    }

    result = %{
      scanner_version: "1",
      summary: %{
        confirmed_count: 1,
        possible_count: 0,
        high_sensitivity_count: 1,
        files_scanned: 2,
        errors: 0
      },
      inventory: %{modules: ["MyApp.User"], field_count: 1},
      findings: [finding],
      errors: []
    }

    json = JSON.render(result)

    assert json.scanner_version == "1"
    assert json.summary.confirmed_count == 1
    assert json.inventory.field_count == 1
    assert length(json.findings) == 1
    assert hd(json.findings).classification == :confirmed_pii
    assert hd(hd(json.findings).evidence).type == :direct_field_access
  end
end
