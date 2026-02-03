defmodule PrivSignal.Analysis.Events do
  @moduledoc false

  def from_payload(payload) when is_map(payload) do
    flows = build_events(payload, "touched_flows", :flow_touched, :flow_id)
    pii = build_events(payload, "new_pii", :new_pii, :pii_category)
    sinks = build_events(payload, "new_sinks", :new_sink, :sink)

    flows ++ pii ++ sinks
  end

  defp build_events(payload, key, type, id_key) do
    payload
    |> Map.get(key, [])
    |> Enum.map(fn item ->
      base = %{
        id: unique_id(),
        type: type,
        evidence: get(item, :evidence),
        summary: get(item, :summary),
        confidence: get(item, :confidence)
      }

      base =
        case get(item, :flow_id) do
          nil -> base
          flow_id -> Map.put(base, :flow_id, flow_id)
        end

      case id_key do
        :flow_id -> Map.put(base, :flow_id, get(item, id_key))
        :pii_category -> Map.put(base, :pii_category, get(item, id_key))
        :sink -> Map.put(base, :sink, get(item, id_key))
        _ -> base
      end
    end)
  end

  defp unique_id do
    "evt_" <> Integer.to_string(:erlang.unique_integer([:positive, :monotonic]))
  end

  defp get(map, key) when is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
