defmodule PrivSignal.Infer.FlowBuilderTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.FlowBuilder

  test "builds one flow per source reference and sink in same unit" do
    result = FlowBuilder.build(sample_nodes())

    assert result.candidate_count == 2
    assert length(result.flows) == 2

    assert Enum.any?(result.flows, fn flow ->
             flow.source == "MyApp.User.email" and
               flow.entrypoint == "MyAppWeb.UserController.create/2" and
               flow.boundary == "internal"
           end)

    assert Enum.all?(result.flows, &is_list(&1.evidence))
    assert Enum.all?(result.flows, &String.starts_with?(&1.id, "psf_"))
  end

  test "marks external boundary for outbound sink kinds" do
    [http_node | _] = sample_nodes()
    http_node = put_in(http_node, [:role, :kind], "http")
    nodes = [http_node | tl(sample_nodes())]

    %{flows: [flow | _]} = FlowBuilder.build(nodes)
    assert flow.boundary == "external"
  end

  test "returns no flows when no sink is present" do
    only_entrypoint =
      sample_nodes()
      |> Enum.filter(&(&1.node_type == "entrypoint"))

    assert %{flows: [], candidate_count: 0} = FlowBuilder.build(only_entrypoint)
  end

  defp sample_nodes do
    [
      %{
        id: "psn_sink_1",
        node_type: "sink",
        pii: [
          %{reference: "MyApp.User.email", category: "contact", sensitivity: "high"},
          %{reference: "MyApp.User.phone", category: "contact", sensitivity: "medium"}
        ],
        code_context: %{
          module: "MyAppWeb.UserController",
          function: "create/2",
          file_path: "lib/my_app_web/controllers/user_controller.ex"
        },
        role: %{kind: "logger", callee: "Logger.info"},
        confidence: 1.0,
        evidence: [%{rule: "logging_pii"}]
      },
      %{
        id: "psn_entrypoint_1",
        node_type: "entrypoint",
        pii: [],
        code_context: %{
          module: "MyAppWeb.UserController",
          function: "create/2",
          file_path: "lib/my_app_web/controllers/user_controller.ex"
        },
        role: %{kind: "controller", callee: "module_classification"},
        confidence: 0.9,
        evidence: []
      }
    ]
  end
end
