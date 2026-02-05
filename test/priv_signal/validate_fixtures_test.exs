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

  test "fixture flow fails when an edge is missing" do
    # Skip the middle module to confirm missing edges are reported from the fixture index.
    config = %Config{
      flows: [
        %Flow{
          id: "fixture_flow_missing_edge",
          path: [
            %PathStep{module: "Fixtures.Flow.Start", function: "run"},
            %PathStep{module: "Fixtures.Flow.End", function: "finish"}
          ]
        }
      ]
    }

    assert {:ok, results} = Validate.run(config, index: [root: fixture_root(), paths: ["lib"]])
    assert Validate.status(results) == :error

    result = Enum.find(results, &(&1.flow_id == "fixture_flow_missing_edge"))
    assert Enum.any?(result.errors, &(&1.type == :missing_edge))
  end

  defp fixture_root do
    Path.expand("../fixtures/validate", __DIR__)
  end
end
