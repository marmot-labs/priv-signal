defmodule PrivSignal.Config.PRD do
  @moduledoc false

  alias PrivSignal.Config
  alias PrivSignal.Config.PRDNode

  @classes MapSet.new([
             "direct_identifier",
             "persistent_pseudonymous_identifier",
             "behavioral_signal",
             "inferred_attribute",
             "sensitive_context_indicator"
           ])

  def classes, do: MapSet.to_list(@classes)

  def class?(class) when is_atom(class), do: class?(Atom.to_string(class))

  def class?(class) when is_binary(class) do
    class
    |> String.trim()
    |> String.downcase()
    |> then(&MapSet.member?(@classes, &1))
  end

  def class?(_), do: false

  def entries(%Config{} = config), do: config.prd_nodes || []

  def modules(%Config{} = config) do
    config
    |> entries()
    |> Enum.map(&scope_module/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def nodes_by_token(%Config{} = config) do
    config
    |> entries()
    |> Enum.group_by(&scope_field/1)
    |> Map.drop([nil, ""])
    |> Map.new(fn {token, nodes} -> {token, Enum.sort_by(nodes, &node_sort_key/1)} end)
  end

  defp node_sort_key(node) do
    {
      normalize_string(node.key),
      normalize_string(node.label),
      normalize_string(node.class),
      scope_module(node) || "",
      scope_field(node) || "",
      if(node.sensitive, do: 1, else: 0)
    }
  end

  defp scope_module(%PRDNode{scope: scope}), do: normalize_module(scope && scope.module)
  defp scope_module(_), do: nil

  defp scope_field(%PRDNode{scope: scope}), do: normalize_field(scope && scope.field)
  defp scope_field(_), do: nil

  defp normalize_module("Elixir." <> rest), do: normalize_module(rest)

  defp normalize_module(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_module(_), do: nil

  defp normalize_field(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_field()

  defp normalize_field(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_field(_), do: nil

  defp normalize_string(nil), do: ""
  defp normalize_string(value), do: value |> to_string() |> String.trim()
end
