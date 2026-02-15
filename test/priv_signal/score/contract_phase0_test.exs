defmodule PrivSignal.Score.ContractPhase0Test do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.{Engine, Input, Output}

  test "input contract requires v1 and canonical change fields" do
    with_tmp_file(fn path ->
      File.write!(path, Jason.encode!(%{version: "v1", changes: []}))
      assert {:ok, %{version: "v1", changes: []}} = Input.load_diff_json(path)

      File.write!(path, Jason.encode!(%{changes: []}))
      assert {:error, {:missing_required_field, "version"}} = Input.load_diff_json(path)

      File.write!(path, Jason.encode!(%{version: "v1", changes: [%{"type" => "flow_added"}]}))

      assert {:error, {:invalid_change, %{index: 0, reason: _}}} = Input.load_diff_json(path)
    end)
  end

  test "output contract includes deterministic score fields" do
    diff = %{
      changes: [
        %{
          type: "flow_changed",
          flow_id: "payments",
          change: "external_sink_added",
          severity: "high",
          rule_id: "R-HIGH-EXTERNAL-SINK-ADDED",
          details: %{}
        }
      ]
    }

    assert {:ok, report} = Engine.run(diff, PrivSignal.Config.default_scoring())

    rendered = Output.JSON.render(report)

    assert rendered.version == "v1"
    assert rendered.score in ["NONE", "LOW", "MEDIUM", "HIGH"]
    assert is_integer(rendered.points)
    assert is_map(rendered.summary)
    assert is_list(rendered.reasons)
    assert Map.has_key?(rendered, :llm_interpretation)
  end

  defp with_tmp_file(fun) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "priv_signal_score_contract_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    path = Path.join(dir, "diff.json")
    fun.(path)
  end
end
