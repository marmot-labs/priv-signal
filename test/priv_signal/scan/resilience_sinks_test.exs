defmodule PrivSignal.Scan.ResilienceSinksTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Scan.Runner

  @fixture_root Path.expand("../../fixtures/sinks", __DIR__)

  test "best-effort mode records parse error while still returning sink findings" do
    {:ok, config} = Loader.load(fixture_path("config/valid_sinks_pii.yml"))
    root = make_tmp_dir("scan_resilience_sinks_parse")
    File.mkdir_p!(Path.join(root, "lib"))

    File.cp!(
      fixture_path("lib/fixtures/http_client_sink.ex"),
      Path.join(root, "lib/http_client_sink.ex")
    )

    File.write!(
      Path.join(root, "lib/broken.ex"),
      """
      defmodule Broken do
        def bad(
      end
      """
    )

    assert {:ok, result} =
             Runner.run(config,
               source: [root: root, paths: ["lib"]],
               timeout: 2_000,
               max_concurrency: 1
             )

    assert result.summary.errors == 1
    assert Enum.any?(result.errors, &(&1.type == :parse_error))
    assert Enum.any?(result.findings, &(&1.role_kind == "http"))
  end

  test "strict mode fails when parser errors exist for sinks scan" do
    {:ok, config} = Loader.load(fixture_path("config/valid_sinks_pii.yml"))
    root = make_tmp_dir("scan_resilience_sinks_strict")
    File.mkdir_p!(Path.join(root, "lib"))

    File.write!(Path.join(root, "lib/broken.ex"), "defmodule Broken do\n def bad(\nend\n")

    assert {:error, {:strict_mode_failed, result}} =
             Runner.run(config,
               strict: true,
               source: [root: root, paths: ["lib"]],
               timeout: 1_000,
               max_concurrency: 1
             )

    assert result.summary.errors == 1
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)

  defp make_tmp_dir(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end
end
