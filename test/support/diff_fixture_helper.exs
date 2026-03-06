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
    |> canonicalize_artifact()
  end

  def build_artifact(flows, opts \\ []) when is_list(flows) and is_list(opts) do
    schema_version = Keyword.get(opts, :schema_version, "1")
    data_nodes = Keyword.get(opts, :data_nodes, [])

    %{
      "schema_version" => schema_version,
      "summary" => %{},
      "data_nodes" => data_nodes,
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
    |> Map.put_new("data_nodes", [])
    |> Map.put_new("summary", %{})
    |> Map.put_new("nodes", [])
    |> Map.put_new("errors", [])
    |> Map.put_new("schema_version", "1")
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
    |> Map.put_new("source_class", "direct_identifier")
    |> Map.put_new("source_sensitive", false)
    |> Map.put_new("confidence", 0.0)
    |> maybe_put_location()
  end

  defp maybe_put_location(%{"location" => %{"file_path" => file_path}} = flow)
       when is_binary(file_path) and file_path != "" do
    flow
  end

  defp maybe_put_location(flow) do
    case flow |> Map.get("entrypoint") |> location_from_entrypoint() do
      nil -> flow
      location -> Map.put(flow, "location", location)
    end
  end

  defp location_from_entrypoint(entrypoint) when is_binary(entrypoint) do
    case String.split(entrypoint, ".") do
      [] ->
        nil

      parts ->
        file_path =
          parts
          |> Enum.drop(-1)
          |> module_path()

        case file_path do
          nil -> nil
          path -> %{"file_path" => path, "line" => 1}
        end
    end
  end

  defp location_from_entrypoint(_), do: nil

  defp module_path([]), do: nil

  defp module_path(parts) do
    path =
      parts
      |> Enum.map(&Macro.underscore/1)
      |> Path.join()

    "lib/" <> path <> ".ex"
  end
end
