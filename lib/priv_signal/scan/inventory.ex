defmodule PrivSignal.Scan.Inventory do
  @moduledoc false

  alias PrivSignal.Config
  alias PrivSignal.Config.PRD

  defstruct modules: MapSet.new(),
            data_nodes: [],
            nodes_by_key: %{},
            nodes_by_module: %{},
            key_tokens: MapSet.new(),
            token_nodes: %{},
            # Backward-compatible aliases for scanner internals.
            fields: [],
            fields_by_module: %{},
            token_fields: %{}

  def build(%Config{} = config) do
    data_nodes =
      config
      |> PRD.entries()
      |> Enum.map(fn node ->
        module_name = normalize_module(node.scope && node.scope.module)
        field_name = normalize_token(node.scope && node.scope.field)

        %{
          key: normalize_token(node.key),
          label: normalize_label(node.label),
          class: normalize_class(node.class),
          sensitive: node.sensitive == true,
          module: module_name,
          field: field_name,
          # Alias fields retained for pre-existing scanner code paths.
          name: field_name,
          category: normalize_class(node.class),
          sensitivity: if(node.sensitive == true, do: "high", else: "medium"),
          reference: reference(module_name, field_name)
        }
      end)
      |> Enum.reject(&(is_nil(&1.key) or is_nil(&1.module) or is_nil(&1.field)))
      |> Enum.uniq()
      |> Enum.sort_by(&{&1.key, &1.module, &1.field, &1.class, &1.sensitive})

    modules =
      data_nodes
      |> Enum.map(& &1.module)
      |> MapSet.new()

    nodes_by_key = Map.new(data_nodes, &{&1.key, &1})

    nodes_by_module =
      data_nodes
      |> Enum.group_by(& &1.module)
      |> Map.new(fn {module, entries} ->
        {module, Enum.sort_by(entries, &{&1.field, &1.class, &1.key})}
      end)

    token_nodes =
      data_nodes
      |> Enum.group_by(& &1.field)
      |> Map.new(fn {token, entries} ->
        {token, Enum.sort_by(entries, &{&1.module, &1.class, &1.key})}
      end)

    %__MODULE__{
      modules: modules,
      data_nodes: data_nodes,
      nodes_by_key: nodes_by_key,
      nodes_by_module: nodes_by_module,
      key_tokens: MapSet.new(Map.keys(token_nodes)),
      token_nodes: token_nodes,
      fields: data_nodes,
      fields_by_module: nodes_by_module,
      token_fields: token_nodes
    }
  end

  def nodes_for_token(%__MODULE__{} = inventory, token) do
    Map.get(inventory.token_nodes, normalize_token(token), [])
  end

  def fields_for_token(%__MODULE__{} = inventory, token) do
    nodes_for_token(inventory, token)
  end

  def prd_module?(%__MODULE__{} = inventory, module_name) do
    MapSet.member?(inventory.modules, normalize_module(module_name))
  end

  def pii_module?(%__MODULE__{} = inventory, module_name) do
    prd_module?(inventory, module_name)
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

  defp normalize_label(nil), do: nil

  defp normalize_label(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_label(value), do: value |> to_string() |> normalize_label()

  defp normalize_class(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> "direct_identifier"
      normalized -> normalized
    end
  end

  defp normalize_class(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_class()

  defp normalize_class(_), do: "direct_identifier"

  defp reference(nil, field), do: field
  defp reference(module, nil), do: module
  defp reference(module, field), do: module <> "." <> field

  defp normalize_module("Elixir." <> rest), do: rest

  defp normalize_module(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_module(_), do: nil
end
