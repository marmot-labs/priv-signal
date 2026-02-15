defmodule PrivSignal.Score.RubricV2 do
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

  def classify_events(events, opts \\ []) when is_list(events) do
    strict? = Keyword.get(opts, :strict, false)

    events
    |> Enum.reduce_while({:ok, [], []}, fn event, {:ok, classified, warnings} ->
      case classify_event(event, strict: strict?) do
        {:ok, normalized} ->
          {:cont, {:ok, [normalized | classified], warnings}}

        {:warn, normalized, warning} ->
          {:cont, {:ok, [normalized | classified], [warning | warnings]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, classified, warnings} ->
        {:ok, Enum.reverse(classified), Enum.reverse(warnings)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def classify_event(event, opts \\ []) when is_map(event) do
    strict? = Keyword.get(opts, :strict, false)
    event_type = get(event, :event_type)

    cond do
      MapSet.member?(@known_event_types, event_type) ->
        {event_class, rule_id} = do_classify(event)

        {:ok,
         event
         |> Map.put(:event_class, event_class)
         |> Map.put(:rule_id, Map.get(event, :rule_id) || rule_id)}

      strict? ->
        {:error, {:unknown_event_type, %{event_type: event_type}}}

      true ->
        warning = "unknown event_type in non-strict mode: #{inspect(event_type)}"

        {:warn,
         event
         |> Map.put(:event_class, "low")
         |> Map.put(
           :rule_id,
           Map.get(event, :rule_id) || "R2-LOW-PRIVACY-RELEVANT-RESIDUAL-CHANGE"
         )
         |> Map.put(:unknown_event_type, true), warning}
    end
  end

  defp do_classify(event) do
    case get(event, :event_type) do
      "edge_added" ->
        if get(event, :boundary_after) == "external" do
          {"high", "R2-HIGH-NEW-EXTERNAL-PII-EGRESS"}
        else
          {"medium", "R2-MEDIUM-NEW-INTERNAL-SINK"}
        end

      "destination_changed" ->
        if get(event, :sensitivity_after) == "high" do
          {"high", "R2-HIGH-NEW-VENDOR-HIGH-SENSITIVITY"}
        else
          {"medium", "R2-MEDIUM-BOUNDARY-TIER-INCREASE"}
        end

      "boundary_changed" ->
        case {get(event, :boundary_before), get(event, :boundary_after),
              get(event, :sensitivity_after)} do
          {"internal", "external", "high"} ->
            {"high", "R2-HIGH-EXTERNAL-HIGH-SENSITIVITY-EXPOSURE"}

          {"internal", "external", _} ->
            {"medium", "R2-MEDIUM-BOUNDARY-TIER-INCREASE"}

          _ ->
            {"low", "R2-LOW-PRIVACY-RELEVANT-RESIDUAL-CHANGE"}
        end

      "sensitivity_changed" ->
        case {get(event, :boundary_after), get(event, :sensitivity_before),
              get(event, :sensitivity_after)} do
          {"external", _, "high"} ->
            {"high", "R2-HIGH-EXTERNAL-HIGH-SENSITIVITY-EXPOSURE"}

          {_, before, "medium"} when before in ["low", ""] ->
            {"medium", "R2-MEDIUM-SENSITIVITY-INCREASE-ON-EXISTING-PATH"}

          _ ->
            {"low", "R2-LOW-PRIVACY-RELEVANT-RESIDUAL-CHANGE"}
        end

      "transform_changed" ->
        removed = get_in_map(event, [:transform_delta, :removed], [])

        if get(event, :boundary_after) == "external" and is_list(removed) and removed != [] do
          {"high", "R2-HIGH-EXTERNAL-TRANSFORM-REMOVED"}
        else
          {"low", "R2-LOW-PRIVACY-RELEVANT-RESIDUAL-CHANGE"}
        end

      "edge_updated" ->
        confidence_up? = confidence_up?(event)
        exposure_up? = exposure_up?(event)

        if confidence_up? and exposure_up? do
          {"medium", "R2-MEDIUM-CONFIDENCE-AND-EXPOSURE-INCREASE"}
        else
          {"low", "R2-LOW-PRIVACY-RELEVANT-RESIDUAL-CHANGE"}
        end

      _ ->
        {"low", "R2-LOW-PRIVACY-RELEVANT-RESIDUAL-CHANGE"}
    end
  end

  defp confidence_up?(event) do
    before_conf = get_in_map(event, [:details, :before_confidence], 0.0)
    after_conf = get_in_map(event, [:details, :after_confidence], 0.0)
    as_float(after_conf) > as_float(before_conf)
  end

  defp exposure_up?(event) do
    added_fields = get_in_map(event, [:pii_delta, :added_fields], [])
    is_list(added_fields) and added_fields != []
  end

  defp as_float(value) when is_float(value), do: value
  defp as_float(value) when is_integer(value), do: value * 1.0

  defp as_float(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {parsed, ""} -> parsed
      _ -> 0.0
    end
  end

  defp as_float(_), do: 0.0

  defp get_in_map(map, [key], default) when is_map(map) do
    get(map, key) || default
  end

  defp get_in_map(map, [head | tail], default) when is_map(map) do
    case get(map, head) do
      next when is_map(next) -> get_in_map(next, tail, default)
      _ -> default
    end
  end

  defp get(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
