defmodule PrivSignal.Output.WriterTest do
  use ExUnit.Case

  alias PrivSignal.Output.Writer

  test "writes json output file" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "priv_signal_output_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    json_path = Path.join(tmp_dir, "priv-signal.json")

    assert {:ok, ^json_path} =
             Writer.write("markdown", %{risk_category: :none}, json_path: json_path, quiet: true)

    assert File.exists?(json_path)
  end
end
