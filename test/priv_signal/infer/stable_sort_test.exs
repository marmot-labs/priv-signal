defmodule PrivSignal.Infer.StableSortTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.{Contract, NodeIdentity, NodeNormalizer}

  test "stable_sort_nodes sorts by id then canonical tuple" do
    unsorted =
      [
        node("MyApp.B", "b/1", "lib/b.ex", "logger", "MyApp.User.email"),
        node("MyApp.A", "a/1", "lib/a.ex", "logger", "MyApp.User.email"),
        node("MyApp.C", "c/1", "lib/c.ex", "http", "MyApp.User.phone")
      ]
      |> Enum.map(fn raw ->
        normalized = NodeNormalizer.normalize(raw)
        %{normalized | id: NodeIdentity.id(normalized)}
      end)

    expected =
      unsorted
      |> Enum.sort_by(&NodeNormalizer.sort_key/1)

    assert Contract.stable_sort_nodes(Enum.reverse(unsorted)) == expected
  end

  test "contract validates compatible schema versions" do
    assert Contract.compatible_schema_version?("1")
    refute Contract.compatible_schema_version?("2.0")

    artifact = %{
      schema_version: "1",
      tool: %{name: "priv_signal", version: "0.1.0"},
      git: %{commit: "abc123"},
      summary: %{},
      data_nodes: [],
      nodes: [],
      flows: [],
      errors: []
    }

    assert Contract.valid_artifact?(artifact)

    invalid = Map.put(artifact, :schema_version, "2.0")
    refute Contract.valid_artifact?(invalid)
  end

  defp node(module, function, file_path, kind, reference) do
    %{
      node_type: "sink",
      data_refs: [%{reference: reference, class: "direct_identifier", sensitive: true}],
      code_context: %{module: module, function: function, file_path: file_path, lines: [12]},
      role: %{kind: kind, subtype: "sample"},
      confidence: 1.0,
      evidence: []
    }
  end
end
