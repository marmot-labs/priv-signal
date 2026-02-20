defmodule PrivSignal.Infer.FlowDeterminismPropertyTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.FlowBuilder

  test "flow output is stable across node ordering changes" do
    nodes = sample_nodes()
    baseline = FlowBuilder.build(nodes).flows

    1..10
    |> Enum.each(fn _ ->
      shuffled = Enum.shuffle(nodes)
      assert FlowBuilder.build(shuffled).flows == baseline
    end)
  end

  defp sample_nodes do
    [
      %{
        id: "psn_2",
        node_type: "sink",
        data_refs: [%{reference: "MyApp.User.email", class: "direct_identifier", sensitive: true}],
        code_context: %{
          module: "MyAppWeb.UserController",
          function: "create/2",
          file_path: "lib/my_app_web/controllers/user_controller.ex"
        },
        role: %{kind: "logger", callee: "Logger.info"},
        confidence: 1.0,
        evidence: []
      },
      %{
        id: "psn_1",
        node_type: "sink",
        data_refs: [%{reference: "MyApp.User.phone", class: "direct_identifier", sensitive: true}],
        code_context: %{
          module: "MyAppWeb.UserController",
          function: "create/2",
          file_path: "lib/my_app_web/controllers/user_controller.ex"
        },
        role: %{kind: "logger", callee: "Logger.info"},
        confidence: 1.0,
        evidence: []
      }
    ]
  end
end
