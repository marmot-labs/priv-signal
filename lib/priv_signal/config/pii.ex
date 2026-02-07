defmodule PrivSignal.Config.PII do
  @moduledoc false

  alias PrivSignal.Config
  alias PrivSignal.Config.PIIEntry

  def modules(%Config{} = config) do
    config
    |> entries()
    |> Enum.map(&normalize_module/1)
    |> Enum.uniq()
  end

  def fields(%Config{} = config) do
    config
    |> entries()
    |> Enum.flat_map(fn entry ->
      Enum.map(entry.fields || [], fn field ->
        %{
          module: normalize_module(entry.module),
          name: field.name,
          category: field.category,
          sensitivity: field.sensitivity || "medium"
        }
      end)
    end)
  end

  def key_tokens(%Config{} = config) do
    config
    |> fields()
    |> Enum.map(&normalize_token(&1.name))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def entries(%Config{} = config) do
    config.pii || []
  end

  defp normalize_module(%PIIEntry{module: module}), do: normalize_module(module)
  defp normalize_module("Elixir." <> rest), do: rest
  defp normalize_module(module), do: module

  defp normalize_token(nil), do: nil

  defp normalize_token(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      token -> token
    end
  end

  defp normalize_token(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_token()
  end

  defp normalize_token(_), do: nil
end
