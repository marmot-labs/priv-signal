defmodule Mix.Tasks.PrivSignal.ScoreV2ContractTest do
  use ExUnit.Case

  test "requires diff v2 and emits output version v2" do
    with_tmp_dir(fn ->
      File.write!("priv-signal.yml", valid_yaml())
      File.write!("privacy_diff.json", Jason.encode!(valid_v2_diff(), pretty: true))

      Mix.shell(Mix.Shell.Process)
      Mix.Task.reenable("priv_signal.score")
      Mix.Tasks.PrivSignal.Score.run(["--diff", "privacy_diff.json", "--output", "score.json"])

      payload = File.read!("score.json") |> Jason.decode!()
      assert payload["version"] == "v2"
      refute Map.has_key?(payload, "points")
    end)
  end

  test "fails on legacy diff v1 contract" do
    with_tmp_dir(fn ->
      File.write!("priv-signal.yml", valid_yaml())
      File.write!("privacy_diff.json", Jason.encode!(%{version: "v1", changes: []}, pretty: true))

      Mix.shell(Mix.Shell.Process)
      Mix.Task.reenable("priv_signal.score")

      assert_raise Mix.Error, ~r/score failed/, fn ->
        Mix.Tasks.PrivSignal.Score.run(["--diff", "privacy_diff.json"])
      end

      assert_received {:mix_shell, :error, [message]}
      assert String.contains?(message, "unsupported diff version v1")
    end)
  end

  defp with_tmp_dir(fun) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "priv_signal_score_v2_contract_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    File.cd!(tmp_dir, fun)
  end

  defp valid_yaml do
    """
    version: 1

    pii:
      - module: PrivSignal.Config
        fields:
          - name: email
            category: contact
            sensitivity: medium

    flows: []
    """
  end

  defp valid_v2_diff do
    %{
      version: "v2",
      summary: %{events_total: 1, events_high: 1, events_medium: 0, events_low: 0},
      events: [
        %{
          event_id: "evt:1",
          event_type: "destination_changed",
          event_class: "high",
          edge_id: "payments",
          rule_id: "R2-HIGH-NEW-EXTERNAL-PII-EGRESS"
        }
      ]
    }
  end
end
