defmodule PrivSignal.Config.PII do
  @moduledoc false

  alias PrivSignal.Config
  alias PrivSignal.Config.PRD

  def modules(%Config{} = config) do
    PRD.modules(config)
  end

  def fields(%Config{} = config) do
    config
    |> entries()
    |> Enum.map(fn node ->
      %{
        module: normalize_module(node.scope && node.scope.module),
        name: normalize_token(node.scope && node.scope.field),
        key: node.key,
        label: node.label,
        class: node.class,
        sensitivity: if(node.sensitive, do: "high", else: "medium")
      }
    end)
    |> Enum.reject(&is_nil(&1.name))
  end

  def key_tokens(%Config{} = config) do
    config
    |> fields()
    |> Enum.map(&normalize_token(&1.name))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def entries(%Config{} = config) do
    config.prd_nodes || []
  end

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
