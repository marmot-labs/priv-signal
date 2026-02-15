defmodule PrivSignal.Scan.SinksContractTest do
  use ExUnit.Case, async: true

  @fixture_root Path.expand("../../fixtures/sinks", __DIR__)

  test "phase0 sinks fixtures exist for all categories" do
    assert File.exists?(fixture_path("lib/fixtures/http_client_sink.ex"))
    assert File.exists?(fixture_path("lib/fixtures/controller_response_sink.ex"))
    assert File.exists?(fixture_path("lib/fixtures/telemetry_sink.ex"))
    assert File.exists?(fixture_path("lib/fixtures/database_access.ex"))
    assert File.exists?(fixture_path("lib/fixtures/liveview_sink.ex"))
    assert File.exists?(fixture_path("lib/fixtures/mixed_surface_area.ex"))
  end

  test "phase0 infer lockfile snapshot fixture has required keys" do
    path = fixture_path("expected/infer_lockfile_mixed.json")
    assert File.exists?(path)

    assert {:ok, map} = path |> File.read!() |> Jason.decode()

    for key <- ["schema_version", "tool", "git", "summary", "nodes", "flows", "errors"] do
      assert Map.has_key?(map, key)
    end
  end

  test "phase0 infer snapshot includes contract role kinds" do
    path = fixture_path("expected/infer_lockfile_mixed.json")
    {:ok, map} = path |> File.read!() |> Jason.decode()

    kinds =
      map
      |> Map.fetch!("nodes")
      |> Enum.map(fn node -> get_in(node, ["role", "kind"]) end)
      |> Enum.uniq()
      |> Enum.sort()

    assert Enum.sort([
             "controller",
             "database_read",
             "database_write",
             "http",
             "liveview_render",
             "telemetry"
           ]) ==
             kinds
  end

  @tag :skip
  test "contract: scanner run emits all phase4 sink/source kinds for mixed fixture" do
    flunk("Enable in Phase 2/3 once multi-category scanners are implemented")
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
