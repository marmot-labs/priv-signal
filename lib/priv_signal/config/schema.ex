defmodule PrivSignal.Config.Schema do
  @moduledoc false

  alias PrivSignal.Config

  @required_flow_keys [:id, :description, :purpose, :pii_categories, :path, :exits_system]
  @required_path_keys [:module, :function]
  @scanner_categories [:logging, :http, :controller, :telemetry, :database, :liveview]

  def validate(map) when is_map(map) do
    errors = []
    errors = validate_version(map, errors)
    errors = validate_legacy_pii_modules(map, errors)
    errors = validate_pii(map, errors)
    errors = validate_flows(map, errors)
    errors = validate_scanners(map, errors)

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

  defp validate_legacy_pii_modules(map, errors) do
    if Map.has_key?(map, :pii_modules) or Map.has_key?(map, "pii_modules") do
      ["pii_modules is deprecated; use pii entries with module/fields metadata" | errors]
    else
      errors
    end
  end

  defp validate_pii(map, errors) do
    case get(map, :pii) do
      nil ->
        ["pii is required" | errors]

      list when is_list(list) ->
        Enum.reduce(Enum.with_index(list), errors, fn {entry, idx}, acc ->
          validate_pii_entry(entry, idx, acc)
        end)

      _ ->
        ["pii must be a list" | errors]
    end
  end

  defp validate_pii_entry(entry, idx, errors) when is_map(entry) do
    errors =
      case get(entry, :module) do
        value when is_binary(value) and value != "" -> errors
        _ -> ["pii[#{idx}].module must be a non-empty string" | errors]
      end

    case get(entry, :fields) do
      fields when is_list(fields) and fields != [] ->
        Enum.reduce(Enum.with_index(fields), errors, fn {field, field_idx}, acc ->
          validate_pii_field(field, idx, field_idx, acc)
        end)

      _ ->
        ["pii[#{idx}].fields must be a non-empty list" | errors]
    end
  end

  defp validate_pii_entry(_, idx, errors), do: ["pii[#{idx}] must be a map" | errors]

  defp validate_pii_field(field, idx, field_idx, errors) when is_map(field) do
    errors =
      case get(field, :name) do
        value when is_binary(value) and value != "" -> errors
        _ -> ["pii[#{idx}].fields[#{field_idx}].name must be a non-empty string" | errors]
      end

    errors =
      case get(field, :category) do
        value when is_binary(value) and value != "" -> errors
        _ -> ["pii[#{idx}].fields[#{field_idx}].category must be a non-empty string" | errors]
      end

    case get(field, :sensitivity) do
      nil ->
        errors

      value when value in ["low", "medium", "high"] ->
        errors

      _ ->
        ["pii[#{idx}].fields[#{field_idx}].sensitivity must be low, medium, or high" | errors]
    end
  end

  defp validate_pii_field(_, idx, field_idx, errors) do
    ["pii[#{idx}].fields[#{field_idx}] must be a map" | errors]
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

  defp validate_scanners(map, errors) do
    case get(map, :scanners) do
      nil ->
        errors

      scanners when is_map(scanners) ->
        errors
        |> validate_scanner_unknown_categories(scanners)
        |> validate_logging_scanner(scanners)
        |> validate_http_scanner(scanners)
        |> validate_controller_scanner(scanners)
        |> validate_telemetry_scanner(scanners)
        |> validate_database_scanner(scanners)
        |> validate_liveview_scanner(scanners)

      _ ->
        ["scanners must be a map" | errors]
    end
  end

  defp validate_scanner_unknown_categories(errors, scanners) do
    allowed = MapSet.new(Enum.map(@scanner_categories, &Atom.to_string/1))

    scanners
    |> map_keys_as_strings()
    |> Enum.reject(&MapSet.member?(allowed, &1))
    |> Enum.reduce(errors, fn key, acc ->
      ["scanners.#{key} is not a supported scanner category" | acc]
    end)
  end

  defp validate_http_scanner(errors, scanners) do
    validate_scanner_map(scanners, :http, errors, fn http, acc ->
      acc
      |> validate_scanner_enabled(http, "scanners.http.enabled")
      |> validate_string_list(http, :additional_modules, "scanners.http.additional_modules")
      |> validate_string_list(http, :internal_domains, "scanners.http.internal_domains")
      |> validate_string_list(http, :external_domains, "scanners.http.external_domains")
    end)
  end

  defp validate_logging_scanner(errors, scanners) do
    validate_scanner_map(scanners, :logging, errors, fn logging, acc ->
      acc
      |> validate_scanner_enabled(logging, "scanners.logging.enabled")
      |> validate_string_list(logging, :additional_modules, "scanners.logging.additional_modules")
    end)
  end

  defp validate_controller_scanner(errors, scanners) do
    validate_scanner_map(scanners, :controller, errors, fn controller, acc ->
      acc
      |> validate_scanner_enabled(controller, "scanners.controller.enabled")
      |> validate_string_list(
        controller,
        :additional_render_functions,
        "scanners.controller.additional_render_functions"
      )
    end)
  end

  defp validate_telemetry_scanner(errors, scanners) do
    validate_scanner_map(scanners, :telemetry, errors, fn telemetry, acc ->
      acc
      |> validate_scanner_enabled(telemetry, "scanners.telemetry.enabled")
      |> validate_string_list(
        telemetry,
        :additional_modules,
        "scanners.telemetry.additional_modules"
      )
    end)
  end

  defp validate_database_scanner(errors, scanners) do
    validate_scanner_map(scanners, :database, errors, fn database, acc ->
      acc
      |> validate_scanner_enabled(database, "scanners.database.enabled")
      |> validate_string_list(database, :repo_modules, "scanners.database.repo_modules")
    end)
  end

  defp validate_liveview_scanner(errors, scanners) do
    validate_scanner_map(scanners, :liveview, errors, fn liveview, acc ->
      acc
      |> validate_scanner_enabled(liveview, "scanners.liveview.enabled")
      |> validate_string_list(
        liveview,
        :additional_modules,
        "scanners.liveview.additional_modules"
      )
    end)
  end

  defp validate_scanner_map(scanners, key, errors, validator_fun) do
    case get(scanners, key) do
      nil ->
        errors

      value when is_map(value) ->
        validator_fun.(value, errors)

      _ ->
        ["scanners.#{key} must be a map" | errors]
    end
  end

  defp validate_scanner_enabled(errors, scanner_map, error_path) do
    case get(scanner_map, :enabled) do
      nil -> errors
      value when is_boolean(value) -> errors
      _ -> ["#{error_path} must be a boolean" | errors]
    end
  end

  defp validate_string_list(errors, scanner_map, key, error_path) do
    case get(scanner_map, key) do
      nil ->
        errors

      list when is_list(list) ->
        if Enum.all?(list, &is_binary/1) do
          errors
        else
          ["#{error_path} must be a list of strings" | errors]
        end

      _ ->
        ["#{error_path} must be a list of strings" | errors]
    end
  end

  defp get(map, key) when is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp map_keys_as_strings(map) when is_map(map) do
    Enum.map(Map.keys(map), fn
      key when is_atom(key) -> Atom.to_string(key)
      key when is_binary(key) -> key
      key -> to_string(key)
    end)
  end

  defp list_of_strings?(value) do
    is_list(value) and Enum.all?(value, &is_binary/1)
  end
end
