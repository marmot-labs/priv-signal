defmodule PrivSignal.Diff.Hunks do
  @moduledoc false

  def ranges_by_file(diff) when is_binary(diff) do
    diff
    |> String.split("\n")
    |> Enum.reduce(%{file: nil, ranges: %{}}, fn line, acc ->
      acc
      |> maybe_set_file(line)
      |> maybe_add_hunk(line)
    end)
    |> Map.fetch!(:ranges)
  end

  defp maybe_set_file(%{ranges: ranges} = acc, "+++ " <> rest) do
    file =
      rest
      |> String.trim()
      |> normalize_file()

    %{acc | file: file, ranges: ranges}
  end

  defp maybe_set_file(acc, _line), do: acc

  defp normalize_file("/dev/null"), do: nil
  defp normalize_file("b/" <> path), do: path
  defp normalize_file(path), do: path

  defp maybe_add_hunk(%{file: nil} = acc, _line), do: acc

  defp maybe_add_hunk(%{file: file, ranges: ranges} = acc, "@@ " <> rest) do
    case parse_hunk(rest) do
      {:ok, {start_line, count}} ->
        range = {start_line, start_line + count - 1}
        %{acc | ranges: Map.update(ranges, file, [range], &[range | &1])}

      :error ->
        acc
    end
  end

  defp maybe_add_hunk(acc, _line), do: acc

  defp parse_hunk(rest) do
    case Regex.run(~r/\+([0-9]+)(?:,([0-9]+))?/, rest) do
      [_, start, nil] -> {:ok, {String.to_integer(start), 1}}
      [_, start, count] -> {:ok, {String.to_integer(start), String.to_integer(count)}}
      _ -> :error
    end
  end
end
