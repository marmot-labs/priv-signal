defmodule PrivSignal.Diff.Normalize do
  @moduledoc false

  def normalize(artifact) when is_map(artifact) do
    schema_version = get(artifact, :schema_version)

    flows =
      artifact
      |> get(:flows, [])
      |> Enum.map(&normalize_flow/1)
      |> Enum.sort_by(&flow_sort_key/1)

    %{
      schema_version: schema_version,
      flows: flows,
      flows_by_id: Map.new(flows, &{&1.id, &1}),
      flow_ids: MapSet.new(Enum.map(flows, & &1.id))
    }
  end

  defp normalize_flow(flow) do
    sink = get(flow, :sink, %{})
    source = normalize_source(get(flow, :source))

    %{
      id: normalize_string(get(flow, :id)),
      source: source,
      source_fields: source_fields(source),
      entrypoint: normalize_string(get(flow, :entrypoint)),
      sink: %{
        kind: normalize_string(get(sink, :kind)),
        subtype: normalize_string(get(sink, :subtype))
      },
      boundary: normalize_boundary(get(flow, :boundary)),
      confidence: normalize_confidence(get(flow, :confidence)),
      evidence: normalize_evidence(get(flow, :evidence, []))
    }
  end

  defp flow_sort_key(flow) do
    {
      flow.id,
      flow.source,
      flow.entrypoint,
      flow.sink.kind,
      flow.sink.subtype,
      flow.boundary,
      flow.confidence,
      flow.evidence
    }
  end

  defp source_fields(source) when is_binary(source) do
    source
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn value ->
      case String.split(value, ".", trim: true) do
        [] -> value
        parts -> List.last(parts)
      end
    end)
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  defp source_fields(_), do: MapSet.new()

  defp normalize_source(source) when is_binary(source), do: String.trim(source)
  defp normalize_source(source), do: normalize_string(source)

  defp normalize_evidence(values) when is_list(values) do
    values
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_evidence(_), do: []

  defp normalize_confidence(value) when is_float(value), do: Float.round(value, 4)
  defp normalize_confidence(value) when is_integer(value), do: (value * 1.0) |> Float.round(4)

  defp normalize_confidence(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {parsed, ""} -> Float.round(parsed, 4)
      _ -> 0.0
    end
  end

  defp normalize_confidence(_), do: 0.0

  defp normalize_boundary(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_boundary()

  defp normalize_boundary(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_boundary(_), do: "internal"

  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(value) when is_atom(value), do: value |> Atom.to_string() |> String.trim()
  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)

  defp normalize_string(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 4)

  defp normalize_string(_), do: ""

  defp get(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default
  end
end
