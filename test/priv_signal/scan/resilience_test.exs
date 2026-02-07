defmodule PrivSignal.Scan.ResilienceTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Scan.Runner

  @fixture_root Path.expand("../../fixtures/scan", __DIR__)

  test "records parse errors in best-effort mode" do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))
    root = make_tmp_dir("scan_resilience_parse")
    File.mkdir_p!(Path.join(root, "lib"))

    File.write!(
      Path.join(root, "lib/broken.ex"),
      """
      defmodule Broken do
        def broken(
      end
      """
    )

    assert {:ok, result} =
             Runner.run(config, source: [root: root, paths: ["lib"]], timeout: 1_000)

    assert result.summary.errors == 1
    assert Enum.any?(result.errors, &(&1.type == :parse_error))
  end

  test "strict mode fails when parse errors exist" do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))
    root = make_tmp_dir("scan_resilience_strict")
    File.mkdir_p!(Path.join(root, "lib"))
    File.write!(Path.join(root, "lib/broken.ex"), "defmodule Broken do\ndef bad(\nend\n")

    assert {:error, {:strict_mode_failed, result}} =
             Runner.run(config,
               strict: true,
               source: [root: root, paths: ["lib"]],
               timeout: 1_000
             )

    assert result.summary.errors == 1
  end

  test "records timeout failures as dead-task accounting" do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))
    root = make_tmp_dir("scan_resilience_timeout")
    File.mkdir_p!(Path.join(root, "lib"))
    File.write!(Path.join(root, "lib/file.ex"), "defmodule T do\nend\n")

    scan_fun = fn _file, _inventory ->
      Process.sleep(300)
      {:ok, []}
    end

    assert {:ok, result} =
             Runner.run(config,
               source: [root: root, paths: ["lib"]],
               timeout: 100,
               scan_fun: scan_fun,
               max_concurrency: 1
             )

    assert result.summary.errors == 1
    assert Enum.any?(result.errors, &(&1.type == :timeout || &1.type == :worker_exit))
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)

  defp make_tmp_dir(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end
end
