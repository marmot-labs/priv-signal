defmodule PrivSignal.Config do
  @moduledoc """
  In-memory representation of priv-signal.yml.
  """

  alias PrivSignal.Config.{Flow, PathStep}

  defstruct version: 1, pii_modules: [], flows: []

  defmodule Flow do
    @moduledoc false
    defstruct id: nil,
              description: nil,
              purpose: nil,
              pii_categories: [],
              path: [],
              exits_system: false,
              third_party: nil
  end

  defmodule PathStep do
    @moduledoc false
    defstruct module: nil, function: nil
  end

  @doc false
  def from_map(map) when is_map(map) do
    %__MODULE__{
      version: get(map, :version),
      pii_modules: get(map, :pii_modules) || [],
      flows: Enum.map(get(map, :flows) || [], &flow_from_map/1)
    }
  end

  defp flow_from_map(map) do
    %Flow{
      id: get(map, :id),
      description: get(map, :description),
      purpose: get(map, :purpose),
      pii_categories: get(map, :pii_categories) || [],
      path: Enum.map(get(map, :path) || [], &path_from_map/1),
      exits_system: get(map, :exits_system) || false,
      third_party: get(map, :third_party)
    }
  end

  defp path_from_map(map) do
    %PathStep{module: get(map, :module), function: get(map, :function)}
  end

  defp get(map, key) when is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
