defmodule PrivSignal.Diff.ContractV2 do
  @moduledoc false

  @known_event_types MapSet.new([
                       "node_added",
                       "node_removed",
                       "node_updated",
                       "edge_added",
                       "edge_removed",
                       "edge_updated",
                       "boundary_changed",
                       "sensitivity_changed",
                       "destination_changed",
                       "transform_changed"
                     ])
  @known_event_classes MapSet.new(["high", "medium", "low"])

  def validate_events(events, opts \\ []) when is_list(events) do
    strict? = Keyword.get(opts, :strict, false)

    events
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {event, idx}, {:ok, warnings} ->
      with :ok <- validate_event_shape(event, idx),
           :ok <- validate_required(event, idx),
           :ok <- validate_event_class(event, idx),
           {:ok, new_warnings} <- validate_event_type(event, idx, strict?) do
        {:cont, {:ok, warnings ++ new_warnings}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, warnings} -> {:ok, warnings}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_event_shape(event, _idx) when is_map(event), do: :ok

  defp validate_event_shape(_event, idx),
    do: {:error, {:invalid_event_shape, %{index: idx, reason: "event must be an object"}}}

  defp validate_required(event, idx) do
    with :ok <- require_non_empty_string(event, :event_id, idx),
         :ok <- require_non_empty_string(event, :event_type, idx),
         :ok <- require_node_or_edge(event, idx) do
      :ok
    end
  end

  defp validate_event_class(event, idx) do
    event_class = fetch(event, :event_class)

    if is_binary(event_class) and MapSet.member?(@known_event_classes, event_class) do
      :ok
    else
      {:error, {:invalid_event_class, %{index: idx, event_class: event_class}}}
    end
  end

  defp validate_event_type(event, idx, strict?) do
    event_type = fetch(event, :event_type)

    if MapSet.member?(@known_event_types, event_type) do
      {:ok, []}
    else
      if strict? do
        {:error, {:unknown_event_type, %{index: idx, event_type: event_type}}}
      else
        warning = "unknown event_type in non-strict mode at index #{idx}: #{event_type}"
        {:ok, [warning]}
      end
    end
  end

  defp require_non_empty_string(event, key, idx) do
    value = fetch(event, key)

    if is_binary(value) and String.trim(value) != "" do
      :ok
    else
      {:error, {:missing_required_field, %{index: idx, field: Atom.to_string(key)}}}
    end
  end

  defp require_node_or_edge(event, idx) do
    node_id = fetch(event, :node_id)
    edge_id = fetch(event, :edge_id)

    if present_string?(node_id) or present_string?(edge_id) do
      :ok
    else
      {:error, {:missing_required_field, %{index: idx, field: "node_id_or_edge_id"}}}
    end
  end

  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_), do: false

  defp fetch(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
