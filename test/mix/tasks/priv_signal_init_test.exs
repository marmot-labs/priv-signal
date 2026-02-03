defmodule Mix.Tasks.PrivSignal.InitTest do
  use ExUnit.Case

  test "creates priv-signal.yml in current directory" do
    tmp_dir = Path.join(System.tmp_dir!(), "priv_signal_init_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    File.cd!(tmp_dir, fn ->
      Mix.shell(Mix.Shell.Process)
      Mix.Tasks.PrivSignal.Init.run([])

      assert File.exists?("priv-signal.yml")
    end)
  end
end
