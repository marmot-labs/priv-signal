defmodule Mix.Tasks.PrivSignal.DiffTest do
  use ExUnit.Case

  test "prints usage for --help" do
    Mix.shell(Mix.Shell.Process)
    Mix.Task.reenable("priv_signal.diff")

    Mix.Tasks.PrivSignal.Diff.run(["--help"])

    assert_received {:mix_shell, :info, [message]}
    assert String.contains?(message, "Usage:")
    assert String.contains?(message, "mix priv_signal.diff --base <ref>")
  end

  test "raises when --base is missing" do
    Mix.shell(Mix.Shell.Process)
    Mix.Task.reenable("priv_signal.diff")

    assert_raise Mix.Error, ~r/diff failed/, fn ->
      Mix.Tasks.PrivSignal.Diff.run([])
    end

    assert_received {:mix_shell, :error, ["--base is required"]}
  end
end
