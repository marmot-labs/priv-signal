defmodule PrivSignal.Infer.ResilienceTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Infer.Runner

  @fixture_root Path.expand("../../fixtures/scan", __DIR__)

  test "non-strict mode returns ok with structured parse errors" do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))

    assert {:ok, result} =
             Runner.run(config,
               strict: false,
               source: [root: @fixture_root, paths: ["lib/fixtures"]],
               scan_fun: fn _file, _inventory -> {:error, "synthetic parse failure"} end,
               max_concurrency: 2,
               timeout: 500
             )

    assert result.summary.node_count == 0
    assert result.summary.scan_error_count > 0
    assert Enum.all?(result.errors, &(&1.type == :parse_error))
  end

  test "strict mode returns strict_mode_failed when worker times out" do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))

    assert {:error, {:strict_mode_failed, result}} =
             Runner.run(config,
               strict: true,
               source: [root: @fixture_root, paths: ["lib/fixtures"]],
               scan_fun: fn _file, _inventory ->
                 Process.sleep(250)
                 {:ok, []}
               end,
               max_concurrency: 2,
               timeout: 100
             )

    assert result.summary.scan_error_count > 0
    assert Enum.any?(result.errors, &(&1.type == :timeout))
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
