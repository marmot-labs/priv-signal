defmodule PrivSignal.Infer.ScannerAdapter.LoggingTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.ScannerAdapter.Logging
  alias PrivSignal.Scan.{Evidence, Finding}

  test "maps logging findings to canonical sink nodes with role metadata" do
    finding =
      sample_finding("MyAppWeb.UserController", "lib/my_app_web/controllers/user_controller.ex")

    [node] = Logging.from_findings([finding], root: "/repo")

    assert is_binary(node.id)
    assert node.node_type == "sink"
    assert node.role.kind == "logger"
    assert node.role.callee == "Logger.info"
    refute Map.has_key?(node.role, :arity)
    assert node.code_context.module == "MyAppWeb.UserController"
    assert node.code_context.function == "create/2"
    assert node.code_context.file_path == "lib/my_app_web/controllers/user_controller.ex"
    assert node.entrypoint_context.kind == "controller"
    assert node.entrypoint_context.confidence >= 0.88

    assert Enum.any?(
             node.evidence,
             &(&1.signal == "direct_field_access" and &1.finding_id == "legacy_id")
           )

    assert Enum.any?(node.pii, &(&1.reference == "MyApp.User.email"))
  end

  test "optionally emits standalone entrypoint nodes" do
    finding = sample_finding("MyApp.Workers.ExportWorker", "lib/my_app/workers/export_worker.ex")

    nodes = Logging.from_findings([finding], emit_entrypoint_nodes: true, root: "/repo")

    assert length(nodes) == 2
    assert Enum.any?(nodes, &(&1.node_type == "sink" and &1.role.kind == "logger"))

    assert Enum.any?(nodes, fn node ->
             node.node_type == "entrypoint" and
               node.role.kind == "worker" and
               Enum.any?(node.evidence, &(&1.rule == "entrypoint_classification"))
           end)
  end

  defp sample_finding(module_name, file_path) do
    %Finding{
      id: "legacy_id",
      classification: :confirmed_pii,
      confidence: :confirmed,
      sensitivity: :high,
      module: module_name,
      function: "create",
      arity: 2,
      file: file_path,
      line: 12,
      sink: "Logger.info",
      matched_fields: [
        %{module: "MyApp.User", name: "email", category: "contact", sensitivity: "high"}
      ],
      evidence: [
        %Evidence{
          type: :direct_field_access,
          expression: "user.email",
          fields: [%{module: "MyApp.User", name: "email", sensitivity: "high"}]
        }
      ]
    }
  end
end
