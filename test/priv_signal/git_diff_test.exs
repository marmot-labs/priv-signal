defmodule PrivSignal.Git.DiffTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Git.Diff

  test "returns diff on success" do
    runner = fn _cmd, _args, _opts -> {"diff output", 0} end

    assert {:ok, "diff output"} = Diff.get("main", "HEAD", runner: runner)
  end

  test "returns error on failure" do
    runner = fn _cmd, _args, _opts -> {"fatal: not a git repository", 128} end

    assert {:error, message} = Diff.get("main", "HEAD", runner: runner)
    assert String.contains?(message, "fatal: not a git repository")
  end
end
