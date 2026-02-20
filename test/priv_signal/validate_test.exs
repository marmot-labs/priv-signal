defmodule PrivSignal.ValidateTest do
  use ExUnit.Case

  alias PrivSignal.Config
  alias PrivSignal.Config.{PRDNode, PRDScope}
  alias PrivSignal.Validate

  test "run succeeds when prd module exists in index" do
    config = %Config{
      prd_nodes: [
        %PRDNode{
          key: "config_email",
          label: "Config Email",
          class: "direct_identifier",
          sensitive: true,
          scope: %PRDScope{module: "PrivSignal.Config", field: "email"}
        }
      ]
    }

    assert {:ok, [result]} = Validate.run(config, index: [root: File.cwd!(), paths: ["lib"]])
    assert result.flow_id == "prd_nodes"
    assert result.status == :ok
    assert result.errors == []
  end

  test "run returns missing_prd_module when scope module does not exist" do
    config = %Config{
      prd_nodes: [
        %PRDNode{
          key: "missing_email",
          label: "Missing Email",
          class: "direct_identifier",
          sensitive: true,
          scope: %PRDScope{module: "Missing.PRD.Module", field: "email"}
        }
      ]
    }

    assert {:ok, [result]} = Validate.run(config, index: [root: File.cwd!(), paths: ["lib"]])
    assert result.flow_id == "prd_nodes"
    assert result.status == :error
    assert Enum.any?(result.errors, &(&1.type == :missing_prd_module))
  end
end
