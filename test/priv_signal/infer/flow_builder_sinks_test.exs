defmodule PrivSignal.Infer.FlowBuilderSinksTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.FlowBuilder

  test "treats telemetry, http_response, and liveview_render sinks as external" do
    kinds = ["telemetry", "http_response", "liveview_render"]

    Enum.each(kinds, fn kind ->
      nodes = [
        %{
          id: "sink-#{kind}",
          node_type: "sink",
          data_refs: [%{reference: "MyApp.User.email", class: "direct_identifier", sensitive: true}],
          code_context: %{
            module: "MyApp.Module",
            function: "run/1",
            file_path: "lib/my_app/module.ex"
          },
          role: %{kind: kind, callee: "#{kind}.callee"},
          confidence: 0.9,
          evidence: []
        },
        %{
          id: "src-#{kind}",
          node_type: "source",
          data_refs: [%{reference: "MyApp.User.email", class: "direct_identifier", sensitive: true}],
          code_context: %{
            module: "MyApp.Module",
            function: "run/1",
            file_path: "lib/my_app/module.ex"
          },
          role: %{kind: "database_read", callee: "Repo.get"},
          confidence: 1.0,
          evidence: []
        }
      ]

      %{flows: [flow | _]} = FlowBuilder.build(nodes)
      assert flow.boundary == "external"
    end)
  end
end
