defmodule PrivSignal.Validate.FixturesTest do
  use ExUnit.Case

  alias PrivSignal.Config
  alias PrivSignal.Config.{Flow, PathStep}
  alias PrivSignal.Validate

  test "fixture flow passes with a complete call chain" do
    # Use the fixture source tree so we exercise full index building end-to-end.
    config = %Config{
      flows: [
        %Flow{
          id: "fixture_flow_ok",
          path: [
            %PathStep{module: "Fixtures.Flow.Start", function: "run"},
            %PathStep{module: "Fixtures.Flow.Middle", function: "handle"},
            %PathStep{module: "Fixtures.Flow.End", function: "finish"}
          ]
        }
      ]
    }

    assert {:ok, results} = Validate.run(config, index: [root: fixture_root(), paths: ["lib"]])
    assert Validate.status(results) == :ok
  end

  test "fixture flow passes when symbols exist even if edge is not explicit" do
    # Skip the middle module; symbol-only validation ignores call-edge continuity.
    config = %Config{
      flows: [
        %Flow{
          id: "fixture_flow_symbol_only",
          path: [
            %PathStep{module: "Fixtures.Flow.Start", function: "run"},
            %PathStep{module: "Fixtures.Flow.End", function: "finish"}
          ]
        }
      ]
    }

    assert {:ok, results} = Validate.run(config, index: [root: fixture_root(), paths: ["lib"]])
    assert Validate.status(results) == :ok

    result = Enum.find(results, &(&1.flow_id == "fixture_flow_symbol_only"))
    assert result.status == :ok
    assert result.errors == []
  end

  defp fixture_root do
    Path.expand("../fixtures/validate", __DIR__)
  end
end
