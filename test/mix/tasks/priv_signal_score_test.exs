defmodule Mix.Tasks.PrivSignal.ScoreTest do
  use ExUnit.Case

  test "scores deterministic output from --diff input" do
    with_tmp_dir(fn ->
      File.write!("priv-signal.yml", sample_yaml())
      File.write!("privacy_diff.json", Jason.encode!(sample_diff(), pretty: true))

      Mix.shell(Mix.Shell.Process)
      Mix.Tasks.PrivSignal.Score.run(["--diff", "privacy_diff.json", "--output", "score.json"])

      assert_received {:mix_shell, :info, ["score=HIGH points=9"]}
      assert_received {:mix_shell, :info, ["score output written: score.json"]}

      assert File.exists?("score.json")
      {:ok, output} = File.read("score.json")
      {:ok, payload} = Jason.decode(output)

      assert payload["score"] == "HIGH"
      assert payload["points"] == 9
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

  test "scores without requiring flows in config" do
    with_tmp_dir(fn ->
      File.write!(
        "priv-signal.yml",
        """
        version: 1

        pii:
          - module: PrivSignal.Config
            fields:
              - name: email
                category: contact
                sensitivity: medium
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

    pii:
      - module: PrivSignal.Config
        fields:
          - name: email
            category: contact
            sensitivity: medium

    flows:
      - id: config_load_chain
        description: "Config load chain"
        purpose: setup
        pii_categories:
          - config
        path:
          - module: PrivSignal.Config.Loader
            function: load
          - module: PrivSignal.Config.Schema
            function: validate
          - module: PrivSignal.Config
            function: from_map
        exits_system: false
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
