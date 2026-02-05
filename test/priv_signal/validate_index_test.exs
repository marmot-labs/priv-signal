defmodule PrivSignal.Validate.IndexTest do
  use ExUnit.Case

  alias PrivSignal.Validate.Index

  test "index builder records modules and functions across multiple files" do
    {:ok, index} = Index.build(root: fixture_root(), paths: ["lib"])

    assert MapSet.member?(index.modules, "Fixtures.Flow.Start")
    assert MapSet.member?(index.modules, "Fixtures.Import.Only")

    functions = Map.get(index.functions, "Fixtures.Flow.Start")
    assert MapSet.member?(functions, {"run", 1})
  end

  test "index includes function arities for default arguments" do
    {:ok, index} = Index.build(root: fixture_root(), paths: ["lib"])

    functions = Map.get(index.functions, "Fixtures.Flow.Start")

    assert MapSet.member?(functions, {"run", 1})
  end

  defp fixture_root do
    Path.expand("../fixtures/validate", __DIR__)
  end
end
