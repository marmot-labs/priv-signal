defmodule PrivSignal.Analysis.Validator do
  @moduledoc false

  alias PrivSignal.Diff.Hunks
  alias PrivSignal.LLM.Schema

  @evidence_regex ~r/^(?<file>[^:]+):(?<start>\d+)(?:-(?<end>\d+))?$/

  def validate(payload, diff) when is_map(payload) and is_binary(diff) do
    with {:ok, payload} <- Schema.validate(payload) do
      ranges = Hunks.ranges_by_file(diff)
      {payload, _warnings} = sanitize_payload(payload, ranges)
      {:ok, payload}
    end
  end

  def validate(_, _), do: {:error, ["invalid inputs for validation"]}

  defp sanitize_payload(payload, ranges) do
    {touched_flows, warnings_1} = sanitize_list(payload, "touched_flows", :flow_id, ranges)
    {new_pii, warnings_2} = sanitize_list(payload, "new_pii", :pii_category, ranges)
    {new_sinks, warnings_3} = sanitize_list(payload, "new_sinks", :sink, ranges)

    payload =
      payload
      |> Map.put("touched_flows", touched_flows)
      |> Map.put("new_pii", new_pii)
      |> Map.put("new_sinks", new_sinks)

    {payload, warnings_1 ++ warnings_2 ++ warnings_3}
  end

  defp sanitize_list(payload, key, id_key, ranges) do
    items = Map.get(payload, key, [])

    {kept, warnings} =
      Enum.reduce(Enum.with_index(items), {[], []}, fn {item, idx}, {acc, warns} ->
        id_value = coerce_id(get(item, id_key))
        evidence = coerce_evidence(get(item, :evidence))

        cond do
          is_nil(evidence) ->
            {acc, ["#{key}[#{idx}].evidence missing or invalid" | warns]}

          true ->
            case parse_evidence(evidence) do
              {:ok, {file, start_line, end_line}} ->
                if evidence_in_diff?(file, start_line, end_line, ranges) do
                  canonical = canonical_evidence(file, start_line, end_line)
                  item = put(item, :evidence, canonical)
                  item = if is_nil(id_value), do: item, else: put(item, id_key, id_value)
                  {[item | acc], warns}
                else
                  {acc, ["#{key}[#{idx}].evidence not found in diff: #{evidence}" | warns]}
                end

              {:error, reason} ->
                {acc, ["#{key}[#{idx}].evidence invalid: #{reason}" | warns]}
            end
        end
      end)

    {Enum.reverse(kept), warnings}
  end

  defp parse_evidence(evidence) when is_binary(evidence) do
    trimmed = String.trim(evidence)

    case Regex.named_captures(@evidence_regex, trimmed) do
      %{"file" => file, "start" => start, "end" => nil} ->
        {:ok, {normalize_file(file), String.to_integer(start), String.to_integer(start)}}

      %{"file" => file, "start" => start, "end" => last} ->
        start_i = String.to_integer(start)
        end_i = String.to_integer(last)

        if end_i >= start_i do
          {:ok, {normalize_file(file), start_i, end_i}}
        else
          {:error, "end before start"}
        end

      _ ->
        {:error, "expected format path:line or path:start-end"}
    end
  end

  defp parse_evidence(_), do: {:error, "evidence must be a string"}

  defp canonical_evidence(file, start_line, end_line) do
    if end_line == start_line do
      "#{file}:#{start_line}"
    else
      "#{file}:#{start_line}-#{end_line}"
    end
  end

  defp normalize_file(path) do
    path
    |> String.trim()
    |> String.trim_leading("./")
  end

  defp evidence_in_diff?(file, start_line, end_line, ranges) do
    file_ranges = Map.get(ranges, file) || Map.get(ranges, "#{file}")

    case file_ranges do
      nil -> false
      ranges_list ->
        Enum.any?(ranges_list, fn {start, end_line_in_diff} ->
          start_line <= end_line_in_diff and end_line >= start
        end)
    end
  end

  defp get(map, key) when is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp put(map, key, value) when is_atom(key) do
    cond do
      Map.has_key?(map, key) -> Map.put(map, key, value)
      Map.has_key?(map, Atom.to_string(key)) -> Map.put(map, Atom.to_string(key), value)
      true -> Map.put(map, key, value)
    end
  end

  defp coerce_evidence(nil), do: nil

  defp coerce_evidence(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp coerce_evidence(value) when is_list(value) do
    Enum.find_value(value, &coerce_evidence/1)
  end

  defp coerce_evidence(value) when is_map(value) do
    evidence_from_map(value)
  end

  defp coerce_evidence(_), do: nil

  defp coerce_id(nil), do: nil

  defp coerce_id(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp coerce_id(value) when is_atom(value), do: Atom.to_string(value)
  defp coerce_id(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp coerce_id(_), do: nil

  defp evidence_from_map(map) when is_map(map) do
    file = fetch_any(map, [:file, "file", :path, "path", :filepath, "filepath"])

    {start_line, end_line} =
      case fetch_any(map, [:range, "range", :lines, "lines"]) do
        nil -> {nil, nil}
        range -> parse_line_range(range)
      end

    start_line = start_line || parse_line(fetch_any(map, [:start, "start", :start_line, "start_line", :line, "line"]))
    end_line = end_line || parse_line(fetch_any(map, [:end, "end", :end_line, "end_line"]))

    cond do
      is_binary(file) and is_integer(start_line) and is_integer(end_line) ->
        canonical_evidence(file, start_line, end_line)

      is_binary(file) and is_integer(start_line) ->
        canonical_evidence(file, start_line, start_line)

      true ->
        nil
    end
  end

  defp fetch_any(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} -> value
        :error -> nil
      end
    end)
  end

  defp parse_line_range(nil), do: {nil, nil}

  defp parse_line_range(value) when is_list(value) do
    case value do
      [start_line, end_line] ->
        {parse_line(start_line), parse_line(end_line)}

      [line] ->
        line = parse_line(line)
        {line, line}

      _ ->
        {nil, nil}
    end
  end

  defp parse_line_range(value) when is_binary(value) do
    trimmed = String.trim(value)

    case String.split(trimmed, "-", parts: 2) do
      [start_s, end_s] ->
        {parse_line(start_s), parse_line(end_s)}

      [single] ->
        line = parse_line(single)
        {line, line}
    end
  end

  defp parse_line_range(_), do: {nil, nil}

  defp parse_line(nil), do: nil
  defp parse_line(value) when is_integer(value), do: value

  defp parse_line(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_line(_), do: nil
end
