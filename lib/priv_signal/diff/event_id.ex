defmodule PrivSignal.Diff.EventId do
  @moduledoc false

  def generate(event) when is_map(event) do
    event_type = fetch(event, :event_type, "unknown")
    edge_id = fetch(event, :edge_id, "")
    rule_id = fetch(event, :rule_id, "")

    fingerprint =
      event
      |> canonicalize()
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    "evt:#{event_type}:#{edge_id}:#{rule_id}:#{fingerprint}"
  end

  defp canonicalize(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> {to_string(key), canonicalize(nested)} end)
    |> Enum.sort()
  end

  defp canonicalize(value) when is_list(value), do: Enum.map(value, &canonicalize/1)
  defp canonicalize(value), do: value

  defp fetch(map, key, default) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default
  end
end
