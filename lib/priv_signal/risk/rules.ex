defmodule PrivSignal.Risk.Rules do
  @moduledoc false

  @sensitive_categories ["ssn", "passport", "biometric", "health", "financial", "credit_card"]

  def categorize(events, opts \\ []) when is_list(events) do
    config = %{
      sensitive_categories: Keyword.get(opts, :sensitive_categories, @sensitive_categories)
    }

    cond do
      high_risk?(events, config) -> {:high, reasons(events, config)}
      medium_risk?(events, config) -> {:medium, reasons(events, config)}
      low_risk?(events, config) -> {:low, reasons(events, config)}
      true -> {:none, []}
    end
  end

  defp high_risk?(events, config) do
      new_external_transfer?(events) or
      sensitive_data?(events, config)
  end

  defp medium_risk?(events, _config) do
    new_pii?(events) or
      new_internal_sink?(events)
  end

  defp low_risk?(events, _config) do
    flow_touched?(events)
  end

  defp new_external_transfer?(events) do
    Enum.any?(events, fn event ->
      event.type == :new_sink and
        normalize_string(Map.get(event, :boundary)) == "external"
    end)
  end

  defp new_internal_sink?(events) do
    Enum.any?(events, &(&1.type == :new_sink))
  end

  defp new_pii?(events) do
    Enum.any?(events, &(&1.type == :new_pii))
  end

  defp flow_touched?(events) do
    Enum.any?(events, &(&1.type == :flow_touched))
  end

  defp sensitive_data?(events, config) do
    Enum.any?(events, fn event ->
      event.type == :new_pii and
        normalize_string(event.pii_category) in config.sensitive_categories
    end)
  end

  defp reasons(events, config) do
    reasons = []

    reasons =
      if flow_touched?(events), do: ["Touches existing defined flow" | reasons], else: reasons

    reasons = if new_pii?(events), do: ["Introduces new PII categories" | reasons], else: reasons

    reasons =
      if new_internal_sink?(events), do: ["Introduces new sink/export" | reasons], else: reasons

    reasons =
      if sensitive_data?(events, config) do
        ["Sensitive data categories detected" | reasons]
      else
        reasons
      end

    reasons =
      if new_external_transfer?(events) do
        ["New third-party transfer" | reasons]
      else
        reasons
      end

    Enum.reverse(reasons)
  end

  defp normalize_string(nil), do: nil
  defp normalize_string(value) when is_binary(value), do: String.downcase(String.trim(value))
  defp normalize_string(value), do: to_string(value)
end
