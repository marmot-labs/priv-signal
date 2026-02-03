defmodule PrivSignal.Git.OptionsTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Git.Options

  test "defaults base and head" do
    assert %{base: "origin/main", head: "HEAD"} = Options.parse([])
  end

  test "accepts base and head overrides" do
    assert %{base: "main", head: "feature"} = Options.parse(["--base", "main", "--head", "feature"])
  end
end
