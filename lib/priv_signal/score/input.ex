defmodule PrivSignal.Score.Input do
  @moduledoc false

  @supported_versions MapSet.new(["v2"])

  def load_diff_json(path) when is_binary(path) do
    with {:ok, raw} <- File.read(path),
         {:ok, decoded} <- Jason.decode(raw),
         :ok <- validate(decoded) do
      {:ok, normalize(decoded)}
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:diff_json_parse_failed, Exception.message(error)}}

      {:error, reason} ->
        {:error, reason}

      error ->
        {:error, {:invalid_diff_contract, error}}
    end
  end

  defp validate(decoded) when is_map(decoded) do
    with {:ok, _version} <- validate_version(decoded),
         :ok <- validate_events(decoded) do
      :ok
    end
  end

  defp validate(_), do: {:error, {:invalid_diff_contract, "diff JSON must be an object"}}

  defp validate_version(decoded) do
    version = get(decoded, :version)

    cond do
      not is_binary(version) ->
        {:error, {:missing_required_field, "version"}}

      MapSet.member?(@supported_versions, version) ->
        {:ok, version}

      true ->
        {:error,
         {:unsupported_diff_version,
          %{version: version, supported_versions: MapSet.to_list(@supported_versions)}}}
    end
  end

  defp validate_events(decoded) do
    case get(decoded, :events) do
      events when is_list(events) ->
        events
        |> Enum.with_index()
        |> Enum.reduce_while(:ok, fn {event, idx}, :ok ->
          case validate_event(event) do
            :ok ->
              {:cont, :ok}

            {:error, reason} ->
              {:halt, {:error, {:invalid_event, %{index: idx, reason: reason}}}}
          end
        end)

      _ ->
        {:error, {:missing_required_field, "events"}}
    end
  end

  defp validate_event(event) when is_map(event) do
    with :ok <- require_binary(event, :event_id),
         :ok <- require_binary(event, :event_type),
         :ok <- require_event_class(event),
         :ok <- require_node_or_edge(event),
         :ok <- validate_details(event) do
      :ok
    end
  end

  defp validate_event(_), do: {:error, "event must be an object"}

  defp require_event_class(event) do
    case get(event, :event_class) do
      class when class in ["high", "medium", "low"] -> :ok
      _ -> {:error, "event.event_class must be one of high|medium|low"}
    end
  end

  defp require_node_or_edge(event) do
    node_id = get(event, :node_id)
    edge_id = get(event, :edge_id)

    if present?(node_id) or present?(edge_id) do
      :ok
    else
      {:error, "event must include node_id or edge_id"}
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp validate_details(event) do
    case get(event, :details) do
      nil -> :ok
      details when is_map(details) -> :ok
      _ -> {:error, "event.details must be an object when present"}
    end
  end

  defp require_binary(map, key) do
    case get(map, key) do
      value when is_binary(value) and value != "" -> :ok
      _ -> {:error, "event.#{key} must be a non-empty string"}
    end
  end

  defp normalize(decoded) do
    events =
      decoded
      |> get(:events)
      |> Enum.map(&normalize_event/1)
      |> Enum.sort_by(&sort_key/1)

    %{
      version: get(decoded, :version),
      metadata: get(decoded, :metadata) || %{},
      summary: get(decoded, :summary) || %{},
      events: events
    }
  end

  defp normalize_event(event) do
    %{
      event_id: get(event, :event_id),
      event_type: get(event, :event_type),
      event_class: get(event, :event_class),
      rule_id: get(event, :rule_id),
      node_id: get(event, :node_id),
      edge_id: get(event, :edge_id),
      boundary_before: get(event, :boundary_before),
      boundary_after: get(event, :boundary_after),
      sensitivity_before: get(event, :sensitivity_before),
      sensitivity_after: get(event, :sensitivity_after),
      entrypoint_kind: get(event, :entrypoint_kind),
      destination: get(event, :destination) || %{},
      pii_delta: get(event, :pii_delta) || %{},
      transform_delta: get(event, :transform_delta) || %{},
      details: get(event, :details) || %{}
    }
  end

  defp sort_key(event) do
    {event_class_rank(event.event_class), event.event_type, event.event_id, event.node_id || "",
     event.edge_id || "", stable_map_key(event.details)}
  end

  defp event_class_rank("high"), do: 0
  defp event_class_rank("medium"), do: 1
  defp event_class_rank("low"), do: 2
  defp event_class_rank(_), do: 3

  defp stable_map_key(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), stable_value_key(value)} end)
    |> Enum.sort()
  end

  defp stable_value_key(value) when is_map(value), do: stable_map_key(value)
  defp stable_value_key(value) when is_list(value), do: Enum.map(value, &stable_value_key/1)
  defp stable_value_key(value), do: value

  defp get(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
