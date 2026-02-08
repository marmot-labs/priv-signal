defmodule PrivSignal.Infer.ContractTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.{Contract, NodeIdentity}

  test "artifact contract requires schema envelope keys" do
    artifact = %{
      schema_version: "1.2",
      tool: %{name: "priv_signal", version: "0.1.0"},
      git: %{commit: "abc123"},
      summary: %{node_count: 1, error_count: 0},
      nodes: [node_fixture()],
      flows: [flow_fixture()],
      errors: []
    }

    assert Contract.valid_artifact?(artifact)
  end

  test "node contract requires expected keys and supported node_type" do
    node = node_fixture()
    assert Contract.valid_node?(node)

    invalid = Map.put(node, :node_type, :edge)
    refute Contract.valid_node?(invalid)
  end

  test "deterministic node identity excludes line and evidence ordering" do
    base = node_fixture()

    modified =
      base
      |> put_in([:code_context, :lines], [310])
      |> Map.put(:evidence, Enum.reverse(base.evidence))

    assert NodeIdentity.id(base) == NodeIdentity.id(modified)
  end

  test "deterministic node identity excludes generated_at and run metadata" do
    base = node_fixture()

    node_with_runtime_metadata =
      base
      |> Map.put(:generated_at, "2026-02-08T10:00:00Z")
      |> Map.put(:runtime, %{host: "ci-runner-01", os: "macos"})

    assert NodeIdentity.id(base) == NodeIdentity.id(node_with_runtime_metadata)
  end

  test "stable node sort is deterministic across shuffled input" do
    nodes =
      1..30
      |> Enum.map(fn idx ->
        node =
          node_fixture(%{
            node_type: if(rem(idx, 2) == 0, do: :sink, else: :entrypoint),
            code_context: %{
              module: "MyApp.Module#{idx}",
              function: "run/1",
              file_path: "lib/my_app/module_#{idx}.ex",
              lines: [idx]
            },
            role: %{kind: if(rem(idx, 2) == 0, do: "logger", else: "controller")},
            pii: [%{reference: "MyApp.User.email", category: "contact", sensitivity: "medium"}]
          })

        Map.put(node, :id, NodeIdentity.id(node))
      end)

    expected = Contract.stable_sort_nodes(nodes)

    1..10
    |> Enum.each(fn _ ->
      assert Contract.stable_sort_nodes(Enum.shuffle(nodes)) == expected
    end)
  end

  test "artifact contract remains inference-agnostic" do
    artifact = %{
      schema_version: "1.2",
      tool: %{name: "priv_signal", version: "0.1.0"},
      git: %{commit: "abc123"},
      summary: %{node_count: 1, error_count: 0},
      nodes: [node_fixture()],
      flows: [flow_fixture()],
      errors: []
    }

    refute Map.has_key?(artifact, :edges)
    refute Map.has_key?(artifact, "edges")
  end

  test "flow contract requires expected keys" do
    assert Contract.valid_flow?(flow_fixture())

    invalid = flow_fixture() |> Map.put(:boundary, "internet")
    refute Contract.valid_flow?(invalid)
  end

  defp node_fixture(overrides \\ %{}) do
    default = %{
      id: "psn_seed",
      node_type: :sink,
      pii: [%{reference: "MyApp.User.email", category: "contact", sensitivity: "medium"}],
      code_context: %{
        module: "MyApp.Accounts",
        function: "log_signup/2",
        file_path: "lib/my_app/accounts.ex",
        lines: [42]
      },
      role: %{kind: "logger", subtype: "Logger.info"},
      confidence: 1.0,
      evidence: [
        %{rule: "logging_pii", signal: "logger_call_with_email", line: 42, ast_kind: "call"},
        %{rule: "logging_pii", signal: "pii_field_match", line: 42, ast_kind: "access"}
      ]
    }

    Map.merge(default, overrides)
  end

  defp flow_fixture(overrides \\ %{}) do
    default = %{
      id: "psf_seed",
      source: "MyApp.User.email",
      entrypoint: "MyAppWeb.UserController.create/2",
      sink: %{kind: "logger", subtype: "Logger.info"},
      boundary: "internal",
      confidence: 0.9,
      evidence: ["psn_abc", "psn_def"]
    }

    Map.merge(default, overrides)
  end
end
