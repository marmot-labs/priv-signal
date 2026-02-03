defmodule PrivSignal.LLM.Schema do
  @moduledoc false

  @required_keys ["touched_flows", "new_pii", "new_sinks", "notes"]

  def validate(payload) when is_map(payload) do
    errors = []
    errors = validate_required_keys(payload, errors)
    errors = validate_list(payload, "touched_flows", errors)
    errors = validate_list(payload, "new_pii", errors)
    errors = validate_list(payload, "new_sinks", errors)
    errors = validate_list(payload, "notes", errors)

    if errors == [] do
      {:ok, payload}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  def validate(_), do: {:error, ["llm response must be a map"]}

  defp validate_required_keys(payload, errors) do
    Enum.reduce(@required_keys, errors, fn key, acc ->
      if Map.has_key?(payload, key) do
        acc
      else
        ["missing key: #{key}" | acc]
      end
    end)
  end

  defp validate_list(payload, key, errors) do
    case Map.get(payload, key) do
      list when is_list(list) -> errors
      _ -> ["#{key} must be a list" | errors]
    end
  end
end
