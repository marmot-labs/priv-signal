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
      File.write!("priv_signal.yml", sample_yaml())
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
      refute Map.has_key?(payload, "points")
      assert payload["llm_interpretation"] == nil
    end)
  end

  defp sample_yaml do
    """
    version: 1

    prd_nodes:
      - key: config_email
        label: Config Email
        class: direct_identifier
        sensitive: true
        scope:
          module: PrivSignal.Config
          field: email
    """
  end

  defp sample_diff do
    %{
      version: "v2",
      metadata: %{base_ref: "origin/main"},
      summary: %{events_high: 1, events_medium: 1, events_low: 0, events_total: 2},
      events: [
        %{
          event_id: "evt:payments",
          event_type: "destination_changed",
          event_class: "high",
          edge_id: "payments",
          boundary_after: "external",
          sensitivity_after: "high",
          rule_id: "R2-HIGH-NEW-EXTERNAL-PII-EGRESS",
          details: %{}
        },
        %{
          event_id: "evt:users",
          event_type: "sensitivity_changed",
          event_class: "medium",
          edge_id: "users",
          rule_id: "R2-MEDIUM-SENSITIVITY-INCREASE-ON-EXISTING-PATH",
          details: %{"added_fields" => ["email"]}
        }
      ]
    }
  end
end
