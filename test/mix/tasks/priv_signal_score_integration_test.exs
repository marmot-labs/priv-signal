defmodule Mix.Tasks.PrivSignal.ScoreIntegrationTest do
  use ExUnit.Case

  test "runs pipeline with mocked LLM" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "priv_signal_pipeline_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    try do
      File.cd!(tmp_dir, fn ->
        File.write!("priv-signal.yml", sample_yaml())
        File.write!("priv-signal.json", "")

        mix_file = Path.join(tmp_dir, "mix.exs")
        File.write!(mix_file, "defmodule Dummy do end")

        Mix.shell(Mix.Shell.Process)

        diff = """
        diff --git a/lib/foo.ex b/lib/foo.ex
        index 0000000..1111111 100644
        --- a/lib/foo.ex
        +++ b/lib/foo.ex
        @@ -1,2 +10,3 @@
         defmodule Foo do
        +  def bar, do: :ok
         end
        """

        config = PrivSignal.Config.Loader.load("priv-signal.yml") |> elem(1)
        summary = PrivSignal.Config.Summary.build(config)
        messages = PrivSignal.LLM.Prompt.build(diff, summary)

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

        System.put_env("PRIV_SIGNAL_MODEL_API_KEY", "key")

        result =
          with {:ok, diff} <- {:ok, diff},
               {:ok, raw} <- PrivSignal.LLM.Client.request(messages, request: request),
               {:ok, validated} <- PrivSignal.Analysis.Validator.validate(raw, diff) do
            normalized = PrivSignal.Analysis.Normalizer.normalize(validated)
            events = PrivSignal.Analysis.Events.from_payload(normalized)
            PrivSignal.Risk.Assessor.assess(events, flows: config.flows)
          end

        markdown = PrivSignal.Output.Markdown.render(result)
        json = PrivSignal.Output.JSON.render(result)

        assert {:ok, _path} =
                 PrivSignal.Output.Writer.write(markdown, json,
                   json_path: "priv-signal.json",
                   quiet: true
                 )

        assert File.exists?("priv-signal.json")
      end)
    after
      System.delete_env("PRIV_SIGNAL_MODEL_API_KEY")
    end
  end

  defp sample_yaml do
    """
    version: 1

    pii_modules:
      - PrivSignal.Config

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
end
