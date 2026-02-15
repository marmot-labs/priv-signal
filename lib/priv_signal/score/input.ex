defmodule PrivSignal.Score.Input do
  @moduledoc false

  @supported_versions MapSet.new(["v1"])

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
         :ok <- validate_changes(decoded) do
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

  defp validate_changes(decoded) do
    case get(decoded, :changes) do
      changes when is_list(changes) ->
        changes
        |> Enum.with_index()
        |> Enum.reduce_while(:ok, fn {change, idx}, :ok ->
          case validate_change(change) do
            :ok ->
              {:cont, :ok}

            {:error, reason} ->
              {:halt, {:error, {:invalid_change, %{index: idx, reason: reason}}}}
          end
        end)

      _ ->
        {:error, {:missing_required_field, "changes"}}
    end
  end

  defp validate_change(change) when is_map(change) do
    with :ok <- require_binary(change, :type),
         :ok <- require_binary(change, :change),
         :ok <- require_binary(change, :flow_id),
         :ok <- validate_details(change) do
      :ok
    end
  end

  defp validate_change(_), do: {:error, "change must be an object"}

  defp validate_details(change) do
    case get(change, :details) do
      nil -> :ok
      details when is_map(details) -> :ok
      _ -> {:error, "change.details must be an object when present"}
    end
  end

  defp require_binary(map, key) do
    case get(map, key) do
      value when is_binary(value) and value != "" -> :ok
      _ -> {:error, "change.#{key} must be a non-empty string"}
    end
  end

  defp normalize(decoded) do
    changes =
      decoded
      |> get(:changes)
      |> Enum.map(&normalize_change/1)
      |> Enum.sort_by(&sort_key/1)

    %{
      version: get(decoded, :version),
      metadata: get(decoded, :metadata) || %{},
      summary: get(decoded, :summary) || %{},
      changes: changes
    }
  end

  defp normalize_change(change) do
    %{
      type: get(change, :type),
      flow_id: get(change, :flow_id),
      change: get(change, :change),
      severity: get(change, :severity),
      rule_id: get(change, :rule_id),
      details: get(change, :details) || %{}
    }
  end

  defp sort_key(change) do
    {change.type, change.flow_id, change.change, stable_map_key(change.details)}
  end

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
