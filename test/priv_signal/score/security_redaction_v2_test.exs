defmodule PrivSignal.Score.SecurityRedactionV2Test do
  use ExUnit.Case, async: false

  alias Mix.Tasks.PrivSignal.Score, as: ScoreTask
  alias PrivSignal.Score.{Engine, Output}

  test "score decision log is structured and does not include raw pii values" do
    secret = "alice.sensitive@example.com"

    diff = %{
      metadata: %{strict_mode: false},
      events: [
        %{
          event_id: "evt:h1",
          event_type: "destination_changed",
          boundary_after: "external",
          sensitivity_after: "high",
          details: %{"raw_value" => secret}
        }
      ]
    }

    assert {:ok, report} = Engine.run(diff, PrivSignal.Config.default_scoring())
    rendered = Output.JSON.render(report)
    refute rendered |> Jason.encode!() |> String.contains?(secret)
  end

  test "score task logs sanitized contract failure reason" do
    with_tmp_dir(fn ->
      secret = "alice.sensitive@example.com"

      File.write!("priv-signal.yml", valid_yaml())

      File.write!(
        "privacy_diff.json",
        Jason.encode!(
          %{
            version: "v2",
            metadata: %{strict_mode: false},
            events: [
              %{
                event_type: "destination_changed",
                event_class: "high",
                edge_id: "f1",
                details: %{"raw_value" => secret}
              }
            ]
          },
          pretty: true
        )
      )

      Mix.shell(Mix.Shell.Process)
      Mix.Task.reenable("priv_signal.score")

      assert_raise Mix.Error, ~r/score failed/, fn ->
        ScoreTask.run(["--diff", "privacy_diff.json"])
      end

      assert_received {:mix_shell, :error, [message]}
      assert String.contains?(message, "invalid event")
      refute String.contains?(message, secret)
    end)
  end

  defp with_tmp_dir(fun) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "priv_signal_score_redaction_#{System.unique_integer([:positive])}"
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
end
