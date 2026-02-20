defmodule PrivSignal.ValidateTest do
  use ExUnit.Case

  alias PrivSignal.Config
  alias PrivSignal.Config.{Flow, PRDNode, PRDScope, PathStep}
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

  test "missing prd module produces :missing_prd_module error" do
    config = %Config{
      prd_nodes: [
        %PRDNode{
          key: "missing_email",
          label: "Missing Email",
          class: "direct_identifier",
          sensitive: true,
          scope: %PRDScope{module: "Missing.PII.Module", field: "email"}
        }
      ],
      flows: []
    }

    assert {:ok, [result]} = Validate.run(config, index: [root: fixture_root(), paths: ["lib"]])
    assert result.flow_id == "prd_nodes"
    assert result.status == :error
    assert Enum.any?(result.errors, &(&1.type == :missing_prd_module))
  end

  defp fixture_root do
    Path.expand("../fixtures/validate", __DIR__)
  end
end
