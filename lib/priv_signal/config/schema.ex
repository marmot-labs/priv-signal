defmodule PrivSignal.Config.Schema do
  @moduledoc false

  alias PrivSignal.Config
  alias PrivSignal.Config.PRD

  @required_flow_keys [:id, :description, :purpose, :pii_categories, :path, :exits_system]
  @required_path_keys [:module, :function]
  @scanner_categories [:logging, :http, :controller, :telemetry, :database, :liveview]

  def validate(map, opts \\ [])

  def validate(map, opts) when is_map(map) and is_list(opts) do
    mode = Keyword.get(opts, :mode, :default)
    errors = []
    errors = validate_version(map, errors)
    errors = reject_legacy_pii(map, errors, mode)
    errors = validate_prd_nodes(map, errors, mode)
    errors = validate_flows(map, errors, mode)
    errors = validate_scanners(map, errors)
    errors = validate_scoring(map, errors, mode)

    if errors == [] do
      {:ok, Config.from_map(map)}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  def validate(_, _), do: {:error, ["config must be a map"]}

  defp validate_version(map, errors) do
    case get(map, :version) do
      1 ->
        errors

      nil ->
        ["version is required" | errors]

      other ->
        ["unsupported schema version #{inspect(other)}; only version: 1 is supported" | errors]
    end
  end

  defp reject_legacy_pii(_map, errors, :score), do: errors

  defp reject_legacy_pii(map, errors, _mode) do
    errors =
      if Map.has_key?(map, :pii_modules) or Map.has_key?(map, "pii_modules") do
        ["pii_modules is unsupported in v1; use prd_nodes" | errors]
      else
        errors
      end

    if Map.has_key?(map, :pii) or Map.has_key?(map, "pii") do
      ["pii is unsupported in v1; use prd_nodes" | errors]
    else
      errors
    end
  end

  defp validate_prd_nodes(map, errors, mode) do
    case get(map, :prd_nodes) do
      nil ->
        if mode == :score, do: errors, else: ["prd_nodes is required" | errors]

      list when is_list(list) ->
        errors
        |> validate_prd_node_entries(list)
        |> validate_unique_prd_keys(list)

      _ ->
        ["prd_nodes must be a list" | errors]
    end
  end

  defp validate_prd_node_entries(errors, list) do
    Enum.reduce(Enum.with_index(list), errors, fn {entry, idx}, acc ->
      validate_prd_node(entry, idx, acc)
    end)
  end

  defp validate_prd_node(entry, idx, errors) when is_map(entry) do
    errors =
      case get(entry, :key) do
        value when is_binary(value) ->
          if String.trim(value) == "",
            do: ["prd_nodes[#{idx}].key must be a non-empty string" | errors],
            else: errors

        _ ->
          ["prd_nodes[#{idx}].key must be a non-empty string" | errors]
      end

    errors =
      case get(entry, :label) do
        value when is_binary(value) ->
          if String.trim(value) == "",
            do: ["prd_nodes[#{idx}].label must be a non-empty string" | errors],
            else: errors

        _ ->
          ["prd_nodes[#{idx}].label must be a non-empty string" | errors]
      end

    errors =
      case get(entry, :class) do
        value when is_binary(value) ->
          if PRD.class?(value) do
            errors
          else
            [
              "prd_nodes[#{idx}].class must be one of: #{Enum.join(PRD.classes() |> Enum.sort(), ", ")}"
              | errors
            ]
          end

        _ ->
          [
            "prd_nodes[#{idx}].class must be one of: #{Enum.join(PRD.classes() |> Enum.sort(), ", ")}"
            | errors
          ]
      end

    errors =
      case get(entry, :sensitive) do
        value when is_boolean(value) -> errors
        _ -> ["prd_nodes[#{idx}].sensitive must be a boolean" | errors]
      end

    case get(entry, :scope) do
      scope when is_map(scope) ->
        validate_prd_scope(scope, idx, errors)

      _ ->
        ["prd_nodes[#{idx}].scope must be a map" | errors]
    end
  end

  defp validate_prd_node(_, idx, errors), do: ["prd_nodes[#{idx}] must be a map" | errors]

  defp validate_prd_scope(scope, idx, errors) do
    errors =
      case get(scope, :module) do
        value when is_binary(value) ->
          if String.trim(value) == "",
            do: ["prd_nodes[#{idx}].scope.module must be a non-empty string" | errors],
            else: errors

        _ ->
          ["prd_nodes[#{idx}].scope.module must be a non-empty string" | errors]
      end

    case get(scope, :field) do
      value when is_binary(value) ->
        if String.trim(value) == "",
          do: ["prd_nodes[#{idx}].scope.field must be a non-empty string" | errors],
          else: errors

      _ ->
        ["prd_nodes[#{idx}].scope.field must be a non-empty string" | errors]
    end
  end

  defp validate_unique_prd_keys(errors, list) do
    keys =
      list
      |> Enum.map(&get(&1, :key))
      |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))

    if length(keys) == length(Enum.uniq(keys)) do
      errors
    else
      ["prd_nodes keys must be unique" | errors]
    end
  end

  defp validate_flows(map, errors, mode) do
    case get(map, :flows) do
      nil ->
        if mode == :score do
          errors
        else
          ["flows is required" | errors]
        end

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

  defp validate_scoring(map, errors, mode) do
    case get(map, :scoring) do
      nil ->
        errors

      scoring when is_map(scoring) ->
        if mode == :score do
          errors
          |> reject_legacy_scoring_weights(scoring)
          |> reject_legacy_scoring_thresholds(scoring)
          |> validate_scoring_llm_interpretation(scoring)
        else
          errors
          |> validate_scoring_weights(scoring)
          |> validate_scoring_thresholds(scoring)
          |> validate_scoring_llm_interpretation(scoring)
        end

      _ ->
        ["scoring must be a map" | errors]
    end
  end

  defp reject_legacy_scoring_weights(errors, scoring) do
    if not is_nil(get(scoring, :weights)) do
      ["scoring.weights is unsupported for score v2" | errors]
    else
      errors
    end
  end

  defp reject_legacy_scoring_thresholds(errors, scoring) do
    if not is_nil(get(scoring, :thresholds)) do
      ["scoring.thresholds is unsupported for score v2" | errors]
    else
      errors
    end
  end

  defp validate_scoring_weights(errors, scoring) do
    case get(scoring, :weights) do
      nil ->
        errors

      weights when is_map(weights) ->
        Enum.reduce(weights, errors, fn {rule_id, value}, acc ->
          cond do
            not is_binary(to_string(rule_id)) ->
              ["scoring.weights keys must be strings" | acc]

            not is_integer(value) ->
              ["scoring.weights.#{rule_id} must be an integer" | acc]

            value < 0 ->
              ["scoring.weights.#{rule_id} must be >= 0" | acc]

            true ->
              acc
          end
        end)

      _ ->
        ["scoring.weights must be a map" | errors]
    end
  end

  defp validate_scoring_thresholds(errors, scoring) do
    case get(scoring, :thresholds) do
      nil ->
        errors

      thresholds when is_map(thresholds) ->
        defaults = PrivSignal.Score.Defaults.thresholds()
        low_max = get(thresholds, :low_max) || defaults.low_max
        medium_max = get(thresholds, :medium_max) || defaults.medium_max
        high_min = get(thresholds, :high_min) || defaults.high_min

        errors
        |> validate_non_negative_integer(low_max, "scoring.thresholds.low_max")
        |> validate_non_negative_integer(medium_max, "scoring.thresholds.medium_max")
        |> validate_non_negative_integer(high_min, "scoring.thresholds.high_min")
        |> validate_threshold_monotonic(low_max, medium_max, high_min)

      _ ->
        ["scoring.thresholds must be a map" | errors]
    end
  end

  defp validate_scoring_llm_interpretation(errors, scoring) do
    case get(scoring, :llm_interpretation) do
      nil ->
        errors

      llm when is_map(llm) ->
        errors
        |> validate_boolean(llm, :enabled, "scoring.llm_interpretation.enabled")
        |> validate_optional_non_empty_string(llm, :model, "scoring.llm_interpretation.model")
        |> validate_non_negative_integer(
          get(llm, :timeout_ms),
          "scoring.llm_interpretation.timeout_ms"
        )
        |> validate_non_negative_integer(
          get(llm, :retries),
          "scoring.llm_interpretation.retries"
        )

      _ ->
        ["scoring.llm_interpretation must be a map" | errors]
    end
  end

  defp validate_boolean(errors, map, key, path) do
    case get(map, key) do
      nil -> errors
      value when is_boolean(value) -> errors
      _ -> ["#{path} must be a boolean" | errors]
    end
  end

  defp validate_optional_non_empty_string(errors, map, key, path) do
    case get(map, key) do
      nil ->
        errors

      value when is_binary(value) ->
        if String.trim(value) == "" do
          ["#{path} must be a non-empty string" | errors]
        else
          errors
        end

      _ ->
        ["#{path} must be a non-empty string" | errors]
    end
  end

  defp validate_non_negative_integer(errors, nil, _path), do: errors

  defp validate_non_negative_integer(errors, value, _path)
       when is_integer(value) and value >= 0,
       do: errors

  defp validate_non_negative_integer(errors, _value, path), do: ["#{path} must be >= 0" | errors]

  defp validate_threshold_monotonic(errors, low_max, medium_max, high_min) do
    if low_max < medium_max and medium_max < high_min do
      errors
    else
      ["scoring.thresholds must satisfy low_max < medium_max < high_min" | errors]
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
