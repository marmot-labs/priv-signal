defmodule PrivSignal.Score.ContractV2Test do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.{Input, Output}

  @moduledoc """
  Score v2 input/output contract tests.
  """

  test "accepts only diff version v2 with events[] as score input" do
    with_tmp_file(fn path ->
      File.write!(path, Jason.encode!(%{version: "v2", events: []}))
      assert {:ok, %{version: "v2"}} = Input.load_diff_json(path)

      File.write!(path, Jason.encode!(%{version: "v1", changes: []}))
      assert {:error, {:unsupported_diff_version, %{version: "v1"}}} = Input.load_diff_json(path)
    end)
  end

  test "renders score output version v2 without points field" do
    rendered =
      Output.JSON.render(%{
        score: "LOW",
        summary: %{events_total: 1, events_low: 1},
        reasons: []
      })

    assert rendered.version == "v2"
    refute Map.has_key?(rendered, :points)
    assert rendered.score == "LOW"
  end

  defp with_tmp_file(fun) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "priv_signal_score_contract_v2_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    path = Path.join(dir, "diff.json")
    fun.(path)
  end
end
