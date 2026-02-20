defmodule PrivSignal.Infer.OutputEnvelopeTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Infer.Output.JSON
  alias PrivSignal.Infer.Runner

  @fixture_root Path.expand("../../fixtures/scan", __DIR__)

  test "renders infer envelope with required top-level keys" do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))

    assert {:ok, result} =
             Runner.run(config,
               source: [root: @fixture_root, paths: ["lib/fixtures"]],
               timeout: 2_000,
               max_concurrency: 2
             )

    json = JSON.render(result)

    assert json.schema_version == "1"
    assert is_map(json.tool)
    assert Map.has_key?(json.git, :commit)
    assert is_map(json.summary)
    assert is_list(json.data_nodes)
    assert is_list(json.nodes)
    assert is_list(json.flows)
    assert is_list(json.errors)

    refute Map.has_key?(json, :edges)
    refute Map.has_key?(json, "edges")
  end

  test "infer envelope nodes include canonical contract keys" do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))

    assert {:ok, result} =
             Runner.run(config,
               source: [root: @fixture_root, paths: ["lib/fixtures"]],
               timeout: 2_000,
               max_concurrency: 2
             )

    json = JSON.render(result)

    assert [node | _] = json.nodes

    assert Map.has_key?(node, :id)
    assert Map.has_key?(node, :node_type)
    assert Map.has_key?(node, :data_refs)
    assert Map.has_key?(node, :code_context)
    assert Map.has_key?(node, :role)
    assert Map.has_key?(node, :confidence)
    assert Map.has_key?(node, :evidence)

    assert is_binary(node.id)
    assert node.node_type == "sink"
    assert is_map(node.code_context)
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
