defmodule PrivSignal.ValidateTest do
  use ExUnit.Case

  alias PrivSignal.Config.{Flow, PathStep}
  alias PrivSignal.Validate
  alias PrivSignal.Validate.Error
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

  test "missing edge produces :missing_edge error", %{index: index} do
    flow = %Flow{
      id: "missing_edge",
      path: [
        %PathStep{module: "Fixtures.Flow.Start", function: "run"},
        %PathStep{module: "Fixtures.Flow.End", function: "finish"}
      ]
    }

    result = Validate.validate_flow(flow, index)

    assert Enum.any?(result.errors, &(&1.type == :missing_edge))
  end

  test "ambiguous import produces :ambiguous_call error", %{index: index} do
    flow = %Flow{
      id: "ambiguous_call",
      path: [
        %PathStep{module: "Fixtures.Import.AmbiguousCaller", function: "run"},
        %PathStep{module: "Fixtures.Import.AmbiguousA", function: "shared"}
      ]
    }

    result = Validate.validate_flow(flow, index)

    assert [%Error{type: :ambiguous_call} | _] = result.errors
  end

  defp fixture_root do
    Path.expand("../fixtures/validate", __DIR__)
  end
end
