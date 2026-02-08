defmodule PrivSignal.Infer.DeterminismPropertyTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.NodeIdentity

  test "identity stays stable when only evidence lines shift" do
    baseline = sample_node(100)

    variants =
      1..50
      |> Enum.map(fn n ->
        baseline
        |> put_in([:code_context, :lines], [100 + n])
        |> Map.put(:evidence, [%{rule: "logging_pii", signal: "line_shift", line: 100 + n}])
      end)

    baseline_id = NodeIdentity.id(baseline)

    Enum.each(variants, fn variant ->
      assert NodeIdentity.id(variant) == baseline_id
    end)
  end

  test "identity changes when semantic identity inputs change" do
    node = sample_node(11)

    changed_role = put_in(node, [:role, :kind], "http")
    changed_reference = put_in(node, [:pii, Access.at(0), :reference], "MyApp.User.phone")
    changed_function = put_in(node, [:code_context, :function], "track_signup/1")

    refute NodeIdentity.id(node) == NodeIdentity.id(changed_role)
    refute NodeIdentity.id(node) == NodeIdentity.id(changed_reference)
    refute NodeIdentity.id(node) == NodeIdentity.id(changed_function)
  end

  test "identity is deterministic across randomized ordering and metadata noise" do
    nodes =
      1..200
      |> Enum.map(&sample_node/1)

    baseline = Enum.map(nodes, &NodeIdentity.id/1)

    1..10
    |> Enum.each(fn _ ->
      shuffled = Enum.shuffle(nodes)

      rerun =
        shuffled
        |> Enum.map(fn node ->
          node
          |> Map.put(:runtime, %{host: "runner-#{:rand.uniform(1000)}"})
          |> Map.put(:generated_at, "2026-02-08T11:00:00Z")
          |> Map.put(:evidence, Enum.reverse(node.evidence))
        end)
        |> Enum.sort_by(&semantic_sort_key/1)
        |> Enum.map(&NodeIdentity.id/1)

      expected =
        nodes
        |> Enum.sort_by(&semantic_sort_key/1)
        |> Enum.map(&NodeIdentity.id/1)

      assert rerun == expected
    end)

    assert length(baseline) == 200
  end

  defp semantic_sort_key(node) do
    {
      node.node_type,
      node.code_context.module,
      node.code_context.function,
      node.code_context.file_path,
      node.role.kind,
      node.pii |> Enum.map(& &1.reference) |> Enum.sort()
    }
  end

  defp sample_node(index) do
    %{
      node_type: if(rem(index, 3) == 0, do: :entrypoint, else: :sink),
      pii: [
        %{
          reference: if(rem(index, 5) == 0, do: "MyApp.User.phone", else: "MyApp.User.email"),
          category: "contact",
          sensitivity: if(rem(index, 7) == 0, do: "high", else: "medium")
        }
      ],
      code_context: %{
        module: "MyApp.Context#{rem(index, 13)}",
        function: "handle_#{rem(index, 17)}/2",
        file_path: "lib/my_app/context_#{rem(index, 13)}.ex",
        lines: [index + 10]
      },
      role: %{
        kind: if(rem(index, 3) == 0, do: "controller", else: "logger"),
        subtype: "sample"
      },
      confidence: 0.9,
      evidence: [%{rule: "seed", signal: "s#{index}", line: index + 10, ast_kind: "call"}]
    }
  end
end
