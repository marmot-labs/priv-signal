defmodule Mix.Tasks.PrivSignal.InitTest do
  use ExUnit.Case

  test "creates priv_signal.yml in current directory" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "priv_signal_init_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    File.cd!(tmp_dir, fn ->
      Mix.shell(Mix.Shell.Process)
      Mix.Tasks.PrivSignal.Init.run([])

      assert File.exists?("priv_signal.yml")
      content = File.read!("priv_signal.yml")
      assert String.contains?(content, "prd_nodes:")
      assert String.contains?(content, "scanners:")
      assert String.contains?(content, "logging:")
      assert String.contains?(content, "http:")
      refute String.contains?(content, "pii_modules:")
    end)
  end
end
