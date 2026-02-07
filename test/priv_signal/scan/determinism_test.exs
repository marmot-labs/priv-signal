defmodule PrivSignal.Scan.DeterminismTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Scan.{Classifier, Inventory, Logger, Source}

  @fixture_root Path.expand("../../fixtures/scan", __DIR__)

  test "scanner core output is stable across repeated runs" do
    inventory = fixture_inventory()

    files =
      Source.files(
        root: @fixture_root,
        paths: ["lib/fixtures"]
      )

    assert files == Enum.sort(files)
    assert Enum.any?(files, &String.ends_with?(&1, "confirmed_pii_logging.ex"))

    baseline = run_scan(files, inventory)

    1..10
    |> Enum.each(fn _ ->
      assert run_scan(files, inventory) == baseline
    end)
  end

  defp run_scan(files, inventory) do
    files
    |> Enum.flat_map(fn file ->
      {:ok, candidates} = Logger.scan_file(file, inventory)
      Classifier.classify(candidates)
    end)
    |> Classifier.stable_sort()
  end

  defp fixture_inventory do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))
    Inventory.build(config)
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
