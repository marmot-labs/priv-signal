defmodule PrivSignal.Analysis.Normalizer do
  @moduledoc false

  @default_min_confidence 0.5

  def normalize(payload, opts \\ []) when is_map(payload) do
    min_confidence = Keyword.get(opts, :min_confidence, @default_min_confidence)

    payload
    |> normalize_list("touched_flows", :flow_id, min_confidence)
    |> normalize_list("new_pii", :pii_category, min_confidence)
    |> normalize_list("new_sinks", :sink, min_confidence)
  end

  defp normalize_list(payload, key, id_key, min_confidence) do
    items = Map.get(payload, key, [])

    normalized =
      items
      |> Enum.map(&normalize_item(&1, id_key))
      |> Enum.filter(fn %{confidence: confidence} -> confidence >= min_confidence end)
      |> dedup_items(key, id_key)

    Map.put(payload, key, normalized)
  end

  defp normalize_item(item, id_key) do
    %{}
    |> put(id_key, normalize_string(get(item, id_key)))
    |> Map.put(:flow_id, normalize_string(get(item, :flow_id)))
    |> Map.put(:evidence, normalize_evidence(get(item, :evidence)))
    |> Map.put(:summary, normalize_summary(get(item, :summary)))
    |> Map.put(:confidence, normalize_confidence(get(item, :confidence)))
  end

  defp dedup_items(items, key, id_key) do
    {deduped, _} =
      Enum.reduce(items, {[], MapSet.new()}, fn item, {acc, seen} ->
        token = {key, get(item, id_key), item.evidence}

        if MapSet.member?(seen, token) do
          {acc, seen}
        else
          {[item | acc], MapSet.put(seen, token)}
        end
      end)

    Enum.reverse(deduped)
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_string(value), do: to_string(value)

  defp normalize_confidence(value) when is_float(value) or is_integer(value) do
    value
    |> clamp(0.0, 1.0)
  end

  defp normalize_confidence(_), do: @default_min_confidence

  defp clamp(value, min, _max) when value < min, do: min
  defp clamp(value, _min, max) when value > max, do: max
  defp clamp(value, _min, _max), do: value

  defp normalize_evidence(nil), do: nil

  defp normalize_evidence(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_evidence(value) when is_list(value) do
    Enum.find_value(value, &normalize_evidence/1)
  end

  defp normalize_evidence(value) when is_map(value) do
    evidence_from_map(value)
  end

  defp normalize_evidence(_), do: nil

  defp normalize_summary(nil), do: nil

  defp normalize_summary(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_summary(value) when is_list(value) do
    Enum.find_value(value, &normalize_summary/1)
  end

  defp normalize_summary(_), do: nil

  defp evidence_from_map(map) when is_map(map) do
    file = fetch_any(map, [:file, "file", :path, "path", :filepath, "filepath"])

    {start_line, end_line} =
      case fetch_any(map, [:range, "range", :lines, "lines"]) do
        nil -> {nil, nil}
        range -> parse_line_range(range)
      end

    start_line =
      start_line ||
        parse_line(fetch_any(map, [:start, "start", :start_line, "start_line", :line, "line"]))

    end_line = end_line || parse_line(fetch_any(map, [:end, "end", :end_line, "end_line"]))

    cond do
      is_binary(file) and is_integer(start_line) and is_integer(end_line) ->
        if end_line == start_line do
          "#{file}:#{start_line}"
        else
          "#{file}:#{start_line}-#{end_line}"
        end

      is_binary(file) and is_integer(start_line) ->
        "#{file}:#{start_line}"

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
end
