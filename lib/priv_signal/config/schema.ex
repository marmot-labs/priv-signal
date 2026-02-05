defmodule PrivSignal.Config.Schema do
  @moduledoc false

  alias PrivSignal.Config

  @required_flow_keys [:id, :description, :purpose, :pii_categories, :path, :exits_system]
  @required_path_keys [:module, :function]

  def validate(map) when is_map(map) do
    errors = []
    errors = validate_version(map, errors)
    errors = validate_pii_modules(map, errors)
    errors = validate_flows(map, errors)

    if errors == [] do
      {:ok, Config.from_map(map)}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  def validate(_), do: {:error, ["config must be a map"]}

  defp validate_version(map, errors) do
    case get(map, :version) do
      1 -> errors
      nil -> ["version is required" | errors]
      _ -> ["version must be 1" | errors]
    end
  end

  defp validate_pii_modules(map, errors) do
    case get(map, :pii_modules) do
      nil ->
        ["pii_modules is required" | errors]

      list ->
        if list_of_strings?(list),
          do: errors,
          else: ["pii_modules must be a list of strings" | errors]
    end
  end

  defp validate_flows(map, errors) do
    case get(map, :flows) do
      nil ->
        ["flows is required" | errors]

      list when is_list(list) ->
        Enum.reduce(Enum.with_index(list), errors, fn {flow, idx}, acc ->
          validate_flow(flow, idx, acc)
        end)

      _ ->
        ["flows must be a list" | errors]
    end
  end

  defp validate_flow(flow, idx, errors) when is_map(flow) do
    errors =
      Enum.reduce(@required_flow_keys, errors, fn key, acc ->
        case get(flow, key) do
          nil -> ["flows[#{idx}].#{key} is required" | acc]
          _ -> acc
        end
      end)

    errors = validate_flow_types(flow, idx, errors)
    errors = validate_flow_path(flow, idx, errors)
    errors
  end

  defp validate_flow(_, idx, errors), do: ["flows[#{idx}] must be a map" | errors]

  defp validate_flow_types(flow, idx, errors) do
    errors =
      case get(flow, :id) do
        value when is_binary(value) and value != "" -> errors
        _ -> ["flows[#{idx}].id must be a non-empty string" | errors]
      end

    errors =
      case get(flow, :pii_categories) do
        list ->
          if list_of_strings?(list),
            do: errors,
            else: ["flows[#{idx}].pii_categories must be a list of strings" | errors]
      end

    case get(flow, :exits_system) do
      value when is_boolean(value) -> errors
      _ -> ["flows[#{idx}].exits_system must be a boolean" | errors]
    end
  end

  defp validate_flow_path(flow, idx, errors) do
    case get(flow, :path) do
      list when is_list(list) ->
        Enum.reduce(Enum.with_index(list), errors, fn {step, sidx}, acc ->
          validate_path_step(step, idx, sidx, acc)
        end)

      _ ->
        ["flows[#{idx}].path must be a list" | errors]
    end
  end

  defp validate_path_step(step, fidx, sidx, errors) when is_map(step) do
    errors =
      Enum.reduce(@required_path_keys, errors, fn key, acc ->
        case get(step, key) do
          nil -> ["flows[#{fidx}].path[#{sidx}].#{key} is required" | acc]
          _ -> acc
        end
      end)

    errors =
      case get(step, :module) do
        value when is_binary(value) and value != "" -> errors
        _ -> ["flows[#{fidx}].path[#{sidx}].module must be a string" | errors]
      end

    case get(step, :function) do
      value when is_binary(value) and value != "" -> errors
      _ -> ["flows[#{fidx}].path[#{sidx}].function must be a string" | errors]
    end
  end

  defp validate_path_step(_, fidx, sidx, errors) do
    ["flows[#{fidx}].path[#{sidx}] must be a map" | errors]
  end

  defp get(map, key) when is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp list_of_strings?(value) do
    is_list(value) and Enum.all?(value, &is_binary/1)
  end
end
