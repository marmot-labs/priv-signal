defmodule PrivSignal.Scan.Inventory do
  @moduledoc false

  alias PrivSignal.Config
  alias PrivSignal.Config.PII

  defstruct modules: MapSet.new(),
            fields: [],
            fields_by_module: %{},
            key_tokens: MapSet.new(),
            token_fields: %{}

  def build(%Config{} = config) do
    fields =
      config
      |> PII.fields()
      |> Enum.map(fn field ->
        %{
          module: normalize_module(field.module),
          name: normalize_token(field.name),
          category: field.category,
          sensitivity: field.sensitivity || "medium"
        }
      end)
      |> Enum.reject(&is_nil(&1.name))
      |> Enum.uniq()
      |> Enum.sort_by(&{&1.module, &1.name, &1.category, &1.sensitivity})

    modules =
      fields
      |> Enum.map(& &1.module)
      |> MapSet.new()

    fields_by_module =
      fields
      |> Enum.group_by(& &1.module)
      |> Map.new(fn {module, entries} ->
        {module, Enum.sort_by(entries, &{&1.name, &1.category, &1.sensitivity})}
      end)

    token_fields =
      fields
      |> Enum.group_by(& &1.name)
      |> Map.new(fn {token, entries} ->
        {token, Enum.sort_by(entries, &{&1.module, &1.category, &1.sensitivity})}
      end)

    %__MODULE__{
      modules: modules,
      fields: fields,
      fields_by_module: fields_by_module,
      key_tokens: MapSet.new(Map.keys(token_fields)),
      token_fields: token_fields
    }
  end

  def fields_for_token(%__MODULE__{} = inventory, token) do
    Map.get(inventory.token_fields, normalize_token(token), [])
  end

  def pii_module?(%__MODULE__{} = inventory, module_name) do
    MapSet.member?(inventory.modules, normalize_module(module_name))
  end

  def key_token?(%__MODULE__{} = inventory, token) do
    MapSet.member?(inventory.key_tokens, normalize_token(token))
  end

  defp normalize_token(nil), do: nil

  defp normalize_token(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_token()
  end

  defp normalize_token(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      token -> token
    end
  end

  defp normalize_token(_), do: nil

  defp normalize_module("Elixir." <> rest), do: rest
  defp normalize_module(value), do: value
end
