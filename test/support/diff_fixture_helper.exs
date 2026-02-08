defmodule PrivSignal.Test.DiffFixtureHelper do
  @moduledoc false

  @fixtures_root Path.expand("../fixtures/diff", __DIR__)

  def fixtures_root, do: @fixtures_root

  def fixture_path(scenario, side) when side in [:base, :candidate] do
    Path.join([@fixtures_root, scenario, "#{side}.json"])
  end

  def load_fixture!(scenario, side) when side in [:base, :candidate] do
    scenario
    |> fixture_path(side)
    |> File.read!()
    |> Jason.decode!()
  end

  def build_artifact(flows, opts \\ []) when is_list(flows) and is_list(opts) do
    schema_version = Keyword.get(opts, :schema_version, "1.2")

    %{
      "schema_version" => schema_version,
      "summary" => %{},
      "nodes" => [],
      "flows" =>
        flows
        |> Enum.map(&canonicalize_flow/1)
        |> Enum.sort_by(&Map.get(&1, "id", "")),
      "errors" => []
    }
  end

  def write_fixture!(path, artifact) when is_binary(path) and is_map(artifact) do
    artifact =
      artifact
      |> canonicalize_artifact()
      |> Jason.encode!(pretty: true)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, artifact)
    path
  end

  defp canonicalize_artifact(artifact) do
    flows =
      artifact
      |> Map.get("flows", [])
      |> Enum.map(&canonicalize_flow/1)
      |> Enum.sort_by(&Map.get(&1, "id", ""))

    artifact
    |> Map.put("flows", flows)
    |> Map.put_new("summary", %{})
    |> Map.put_new("nodes", [])
    |> Map.put_new("errors", [])
    |> Map.put_new("schema_version", "1.2")
  end

  defp canonicalize_flow(flow) do
    evidence =
      flow
      |> Map.get("evidence", [])
      |> Enum.map(&to_string/1)
      |> Enum.uniq()
      |> Enum.sort()

    flow
    |> Map.put("evidence", evidence)
    |> Map.put_new("sink", %{})
    |> Map.put_new("boundary", "internal")
    |> Map.put_new("confidence", 0.0)
  end
end
