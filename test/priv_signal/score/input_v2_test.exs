defmodule PrivSignal.Score.InputV2Test do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.Input

  test "loads and deterministically sorts v2 events" do
    with_tmp_file(fn path ->
      diff = %{
        version: "v2",
        events: [
          %{event_id: "evt:b", event_type: "edge_added", event_class: "medium", edge_id: "z"},
          %{
            event_id: "evt:a",
            event_type: "destination_changed",
            event_class: "high",
            edge_id: "a"
          }
        ]
      }

      File.write!(path, Jason.encode!(diff))

      assert {:ok, loaded} = Input.load_diff_json(path)
      assert loaded.version == "v2"
      assert Enum.map(loaded.events, & &1.event_id) == ["evt:a", "evt:b"]
    end)
  end

  test "rejects legacy v1 changes contract" do
    with_tmp_file(fn path ->
      File.write!(path, Jason.encode!(%{version: "v1", changes: []}))
      assert {:error, {:unsupported_diff_version, %{version: "v1"}}} = Input.load_diff_json(path)
    end)
  end

  defp with_tmp_file(fun) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "priv_signal_score_input_v2_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    path = Path.join(dir, "diff.json")
    fun.(path)
  end
end
