defmodule PrivSignal.Diff.FixtureHelperTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Test.DiffFixtureHelper

  test "loads prebuilt fixture scenarios" do
    base = DiffFixtureHelper.load_fixture!("no_change", :base)
    candidate = DiffFixtureHelper.load_fixture!("no_change", :candidate)

    assert is_map(base)
    assert is_map(candidate)
    assert Map.get(base, "schema_version") == "1"
  end

  test "build_artifact sorts flows and deduplicates evidence deterministically" do
    artifact =
      DiffFixtureHelper.build_artifact([
        %{"id" => "z_flow", "evidence" => ["b", "a", "a"]},
        %{"id" => "a_flow", "evidence" => ["2", "1"]}
      ])

    assert ["a_flow", "z_flow"] = Enum.map(artifact["flows"], & &1["id"])
    assert ["1", "2"] = Enum.at(artifact["flows"], 0)["evidence"]
    assert ["a", "b"] = Enum.at(artifact["flows"], 1)["evidence"]
  end
end
