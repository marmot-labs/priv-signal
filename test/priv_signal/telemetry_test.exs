defmodule PrivSignal.TelemetryTest do
  use ExUnit.Case, async: false

  test "emits telemetry events for key steps" do
    events = [
      [:priv_signal, :config, :load],
      [:priv_signal, :git, :diff],
      [:priv_signal, :llm, :request],
      [:priv_signal, :risk, :assess],
      [:priv_signal, :output, :write]
    ]

    :telemetry.attach_many(
      "priv_signal-test",
      events,
      &__MODULE__.handle_event/4,
      self()
    )

    tmp_dir =
      Path.join(System.tmp_dir!(), "priv_signal_telemetry_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    config_path = Path.join(tmp_dir, "priv-signal.yml")
    File.write!(config_path, sample_yaml())

    assert {:ok, _config} = PrivSignal.Config.Loader.load(config_path)

    runner = fn _cmd, _args, _opts -> {"diff output", 0} end
    assert {:ok, _} = PrivSignal.Git.Diff.get("main", "HEAD", runner: runner)

    request = fn _opts ->
      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [
             %{
               "message" => %{
                 "content" =>
                   "{\"touched_flows\":[],\"new_pii\":[],\"new_sinks\":[],\"notes\":[]}"
               }
             }
           ]
         }
       }}
    end

    assert {:ok, _} =
             PrivSignal.LLM.Client.request(
               [
                 %{role: "user", content: "hello"}
               ],
               api_key: "key",
               base_url: "https://example.com",
               model: "gpt-5",
               request: request
             )

    _result = PrivSignal.Risk.Assessor.assess([])

    assert {:ok, _} =
             PrivSignal.Output.Writer.write("markdown", %{risk_category: :none},
               json_path: Path.join(tmp_dir, "priv-signal.json"),
               quiet: true
             )

    assert_received {:telemetry, [:priv_signal, :config, :load], _m1, _meta1}
    assert_received {:telemetry, [:priv_signal, :git, :diff], _m2, _meta2}
    assert_received {:telemetry, [:priv_signal, :llm, :request], _m3, _meta3}
    assert_received {:telemetry, [:priv_signal, :risk, :assess], _m4, _meta4}
    assert_received {:telemetry, [:priv_signal, :output, :write], _m5, _meta5}
  after
    :telemetry.detach("priv_signal-test")
  end

  def handle_event(event, measurements, metadata, parent) do
    send(parent, {:telemetry, event, measurements, metadata})
  end

  defp sample_yaml do
    """
    version: 1

    prd_nodes:
      - key: user_email
        label: User Email
        class: direct_identifier
        sensitive: true
        scope:
          module: MyApp.Accounts.User
          field: email

    flows:
      - id: xapi_export
        description: "User activity exported as xAPI statements"
        purpose: analytics
        pii_categories:
          - user_id
        path:
          - module: MyAppWeb.ActivityController
            function: submit
        exits_system: false
    """
  end
end
