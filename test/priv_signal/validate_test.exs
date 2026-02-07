defmodule PrivSignal.ValidateTest do
  use ExUnit.Case

  alias PrivSignal.Config
  alias PrivSignal.Config.{Flow, PIIEntry, PIIField, PathStep}
  alias PrivSignal.Validate
  alias PrivSignal.Validate.Index

  setup_all do
    {:ok, index} = Index.build(root: fixture_root(), paths: ["lib"])
    {:ok, index: index}
  end

  test "missing module produces :missing_module error", %{index: index} do
    flow = %Flow{id: "missing_module", path: [%PathStep{module: "Missing.Mod", function: "run"}]}

    result = Validate.validate_flow(flow, index)

    assert Enum.any?(result.errors, &(&1.type == :missing_module))
  end

  test "valid flow passes with no errors", %{index: index} do
    flow = %Flow{
      id: "valid_flow",
      path: [
        %PathStep{module: "Fixtures.Flow.Start", function: "run"},
        %PathStep{module: "Fixtures.Flow.Middle", function: "handle"},
        %PathStep{module: "Fixtures.Flow.End", function: "finish"}
      ]
    }

    result = Validate.validate_flow(flow, index)

    assert result.status == :ok
    assert result.errors == []
  end

  test "missing function produces :missing_function error", %{index: index} do
    flow = %Flow{
      id: "missing_function",
      path: [%PathStep{module: "Fixtures.Flow.Start", function: "missing"}]
    }

    result = Validate.validate_flow(flow, index)

    assert Enum.any?(result.errors, &(&1.type == :missing_function))
  end

  test "disconnected path still passes when modules/functions exist", %{index: index} do
    flow = %Flow{
      id: "disconnected_path",
      path: [
        %PathStep{module: "Fixtures.Flow.Start", function: "run"},
        %PathStep{module: "Fixtures.Flow.End", function: "finish"}
      ]
    }

    result = Validate.validate_flow(flow, index)

    assert result.status == :ok
    assert result.errors == []
  end

  test "missing pii module produces :missing_pii_module error" do
    config = %Config{
      pii: [
        %PIIEntry{
          module: "Missing.PII.Module",
          fields: [%PIIField{name: "email", category: "contact", sensitivity: "medium"}]
        }
      ],
      flows: []
    }

    assert {:ok, [result]} = Validate.run(config, index: [root: fixture_root(), paths: ["lib"]])
    assert result.flow_id == "pii"
    assert result.status == :error
    assert Enum.any?(result.errors, &(&1.type == :missing_pii_module))
  end

  defp fixture_root do
    Path.expand("../fixtures/validate", __DIR__)
  end
end
