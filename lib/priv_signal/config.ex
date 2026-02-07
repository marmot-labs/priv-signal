defmodule PrivSignal.Config do
  @moduledoc """
  In-memory representation of priv-signal.yml.
  """

  alias PrivSignal.Config.{Flow, PIIEntry, PIIField, PathStep}

  defstruct version: 1, pii: [], flows: []

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

  defmodule PIIEntry do
    @moduledoc false
    defstruct module: nil, fields: []
  end

  defmodule PIIField do
    @moduledoc false
    defstruct name: nil, category: nil, sensitivity: "medium"
  end

  @doc false
  def from_map(map) when is_map(map) do
    %__MODULE__{
      version: get(map, :version),
      pii: Enum.map(get(map, :pii) || [], &pii_entry_from_map/1),
      flows: Enum.map(get(map, :flows) || [], &flow_from_map/1)
    }
  end

  defp pii_entry_from_map(map) do
    %PIIEntry{
      module: get(map, :module),
      fields: Enum.map(get(map, :fields) || [], &pii_field_from_map/1)
    }
  end

  defp pii_field_from_map(map) do
    %PIIField{
      name: get(map, :name),
      category: get(map, :category),
      sensitivity: get(map, :sensitivity) || "medium"
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
