defmodule PrivSignal.Scan.Source do
  @moduledoc false

  def files(opts \\ []) do
    root = Keyword.get(opts, :root, project_root())
    paths = Keyword.get(opts, :paths, elixirc_paths())

    paths
    |> Enum.map(&Path.expand(&1, root))
    |> Enum.flat_map(&source_files_for_path/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp source_files_for_path(path) do
    ex_files = Path.wildcard(Path.join(path, "**/*.ex"))
    exs_files = Path.wildcard(Path.join(path, "**/*.exs"))
    ex_files ++ exs_files
  end

  defp project_root do
    File.cwd!()
  end

  defp elixirc_paths do
    Mix.Project.config()
    |> Keyword.get(:elixirc_paths, ["lib"])
  end
end
