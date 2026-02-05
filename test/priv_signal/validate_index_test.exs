defmodule PrivSignal.Validate.IndexTest do
  use ExUnit.Case

  alias PrivSignal.Validate.Index

  test "index builder records modules and functions across multiple files" do
    {:ok, index} = Index.build(root: fixture_root(), paths: ["lib"])

    assert MapSet.member?(index.modules, "Fixtures.Flow.Start")
    assert MapSet.member?(index.modules, "Fixtures.Alias.Target")

    functions = Map.get(index.functions, "Fixtures.Flow.Start")
    assert MapSet.member?(functions, {"run", 1})
  end

  test "alias resolution maps remote calls to full module names" do
    {:ok, index} = Index.build(root: fixture_root(), paths: ["lib"])

    caller = {"Fixtures.Alias.Caller", "run", 1}
    callees = Map.get(index.calls, caller)

    assert MapSet.member?(callees, {"Fixtures.Alias.Target", "call", 1})
  end

  test "import resolution respects only filters" do
    {:ok, index} = Index.build(root: fixture_root(), paths: ["lib"])

    caller = {"Fixtures.Import.Caller", "run", 1}
    callees = Map.get(index.calls, caller)

    assert MapSet.member?(callees, {"Fixtures.Import.Only", "allowed", 1})
    refute MapSet.member?(callees, {"Fixtures.Import.Only", "blocked", 1})
  end

  test "ambiguous imports are recorded" do
    {:ok, index} = Index.build(root: fixture_root(), paths: ["lib"])

    caller = {"Fixtures.Import.AmbiguousCaller", "run", 1}
    entries = Map.get(index.ambiguous_calls, caller, [])

    assert Enum.any?(entries, fn entry ->
             entry.function == "shared" and
               MapSet.member?(entry.candidates, "Fixtures.Import.AmbiguousA") and
               MapSet.member?(entry.candidates, "Fixtures.Import.AmbiguousB")
           end)
  end

  defp fixture_root do
    Path.expand("../fixtures/validate", __DIR__)
  end
end
