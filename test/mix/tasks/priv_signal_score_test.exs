defmodule Mix.Tasks.PrivSignal.ScoreTest do
  use ExUnit.Case

  test "scores deterministic output from --diff input" do
    with_tmp_dir(fn ->
      File.write!("priv-signal.yml", sample_yaml())
      File.write!("privacy_diff.json", Jason.encode!(sample_diff(), pretty: true))

      Mix.shell(Mix.Shell.Process)
      Mix.Tasks.PrivSignal.Score.run(["--diff", "privacy_diff.json", "--output", "score.json"])

      assert_received {:mix_shell, :info, ["score=HIGH"]}
      assert_received {:mix_shell, :info, ["score output written: score.json"]}

      assert File.exists?("score.json")
      {:ok, output} = File.read("score.json")
      {:ok, payload} = Jason.decode(output)

      assert payload["score"] == "HIGH"
      refute Map.has_key?(payload, "points")
      assert is_list(payload["reasons"])
    end)
  end

  test "fails when --diff is missing" do
    with_tmp_dir(fn ->
      File.write!("priv-signal.yml", sample_yaml())
      Mix.shell(Mix.Shell.Process)

      assert_raise Mix.Error, ~r/score failed/, fn ->
        Mix.Tasks.PrivSignal.Score.run([])
      end

      assert_received {:mix_shell, :error, ["--diff is required"]}
    end)
  end

  test "scores with minimal prd_nodes config" do
    with_tmp_dir(fn ->
      File.write!(
        "priv-signal.yml",
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
      )

      File.write!("privacy_diff.json", Jason.encode!(sample_diff(), pretty: true))

      Mix.shell(Mix.Shell.Process)
      Mix.Tasks.PrivSignal.Score.run(["--diff", "privacy_diff.json", "--output", "score.json"])

      assert File.exists?("score.json")
    end)
  end

  test "fails when diff json is malformed" do
    with_tmp_dir(fn ->
      File.write!("priv-signal.yml", sample_yaml())
      File.write!("privacy_diff.json", "{not json")

      Mix.shell(Mix.Shell.Process)

      assert_raise Mix.Error, ~r/score failed/, fn ->
        Mix.Tasks.PrivSignal.Score.run(["--diff", "privacy_diff.json"])
      end

      assert_received {:mix_shell, :error, [message]}
      assert String.contains?(message, "diff JSON parse failed")
    end)
  end

  test "fails on unsupported diff schema version" do
    with_tmp_dir(fn ->
      File.write!("priv-signal.yml", sample_yaml())

      invalid_diff = Map.put(sample_diff(), :version, "v9")
      File.write!("privacy_diff.json", Jason.encode!(invalid_diff, pretty: true))

      Mix.shell(Mix.Shell.Process)

      assert_raise Mix.Error, ~r/score failed/, fn ->
        Mix.Tasks.PrivSignal.Score.run(["--diff", "privacy_diff.json"])
      end

      assert_received {:mix_shell, :error, [message]}
      assert String.contains?(message, "unsupported diff version")
    end)
  end

  defp with_tmp_dir(fun) do
    tmp_dir =
      Path.join(System.tmp_dir!(), "priv_signal_score_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    File.cd!(tmp_dir, fn ->
      fun.()
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
