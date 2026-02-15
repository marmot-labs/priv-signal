defmodule Mix.Tasks.PrivSignal.ScoreIntegrationTest do
  use ExUnit.Case

  test "runs score pipeline from diff artifact to score artifact" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "priv_signal_score_pipeline_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    File.cd!(tmp_dir, fn ->
      File.write!("priv-signal.yml", sample_yaml())
      File.write!("privacy_diff.json", Jason.encode!(sample_diff(), pretty: true))

      Mix.shell(Mix.Shell.Process)

      Mix.Tasks.PrivSignal.Score.run([
        "--diff",
        "privacy_diff.json",
        "--output",
        "score.json",
        "--quiet"
      ])

      assert File.exists?("score.json")

      payload = File.read!("score.json") |> Jason.decode!()

      assert payload["score"] == "HIGH"
      assert payload["points"] == 9
      assert payload["llm_interpretation"] == nil
    end)
  end

  defp sample_yaml do
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

  defp sample_diff do
    %{
      version: "v1",
      metadata: %{base_ref: "origin/main"},
      summary: %{high: 1, medium: 1, low: 0, total: 2},
      changes: [
        %{
          type: "flow_changed",
          flow_id: "payments",
          change: "external_sink_added",
          severity: "high",
          rule_id: "R-HIGH-EXTERNAL-SINK-ADDED",
          details: %{}
        },
        %{
          type: "flow_changed",
          flow_id: "users",
          change: "pii_fields_expanded",
          severity: "medium",
          rule_id: "R-MEDIUM-PII-EXPANDED",
          details: %{added_fields: ["email"]}
        }
      ]
    }
  end
end
