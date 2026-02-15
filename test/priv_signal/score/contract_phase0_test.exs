defmodule PrivSignal.Score.ContractPhase0Test do
  use ExUnit.Case, async: true

  alias PrivSignal.Score.{Engine, Input, Output}

  test "input contract requires v2 and canonical event fields" do
    with_tmp_file(fn path ->
      File.write!(path, Jason.encode!(%{version: "v2", events: []}))
      assert {:ok, %{version: "v2", events: []}} = Input.load_diff_json(path)

      File.write!(path, Jason.encode!(%{events: []}))
      assert {:error, {:missing_required_field, "version"}} = Input.load_diff_json(path)

      File.write!(
        path,
        Jason.encode!(%{version: "v2", events: [%{"event_type" => "edge_added"}]})
      )

      assert {:error, {:invalid_event, %{index: 0, reason: _}}} = Input.load_diff_json(path)
    end)
  end

  test "output contract includes deterministic score fields" do
    diff = %{
      events: [
        %{
          event_id: "evt:payments",
          event_type: "destination_changed",
          event_class: "high",
          edge_id: "payments",
          rule_id: "R2-HIGH-NEW-EXTERNAL-PII-EGRESS",
          details: %{}
        }
      ]
    }

    assert {:ok, report} = Engine.run(diff, PrivSignal.Config.default_scoring())

    rendered = Output.JSON.render(report)

    assert rendered.version == "v2"
    assert rendered.score in ["NONE", "LOW", "MEDIUM", "HIGH"]
    refute Map.has_key?(rendered, :points)
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
