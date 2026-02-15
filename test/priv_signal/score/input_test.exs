defmodule PrivSignal.Score.InputTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.Input

  test "loads and normalizes valid diff json" do
    with_tmp_file(fn path ->
      diff = %{
        version: "v1",
        changes: [
          %{type: "flow_added", flow_id: "b", change: "flow_added", details: %{}},
          %{type: "flow_added", flow_id: "a", change: "flow_added", details: %{}}
        ]
      }

      File.write!(path, Jason.encode!(diff))

      assert {:ok, loaded} = Input.load_diff_json(path)
      assert loaded.version == "v1"
      assert Enum.map(loaded.changes, & &1.flow_id) == ["a", "b"]
    end)
  end

  test "returns unsupported diff version error" do
    with_tmp_file(fn path ->
      File.write!(path, Jason.encode!(%{version: "v9", changes: []}))

      assert {:error, {:unsupported_diff_version, %{version: "v9"}}} =
               Input.load_diff_json(path)
    end)
  end

  defp with_tmp_file(fun) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "priv_signal_score_input_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    path = Path.join(dir, "diff.json")
    fun.(path)
  end
end
