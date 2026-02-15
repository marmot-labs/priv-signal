defmodule PrivSignal.Config do
  @moduledoc """
  In-memory representation of priv-signal.yml.
  """

  alias PrivSignal.Config.{
    Flow,
    PIIEntry,
    PIIField,
    PathStep,
    Scanners,
    Scanners.Controller,
    Scanners.Database,
    Scanners.HTTP,
    Scanners.LiveView,
    Scanners.Logging,
    Scanners.Telemetry
  }

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

  defmodule Scanners do
    @moduledoc false

    defmodule HTTP do
      @moduledoc false
      defstruct enabled: true,
                additional_modules: [],
                internal_domains: [],
                external_domains: []
    end

    defmodule Logging do
      @moduledoc false
      defstruct enabled: true, additional_modules: []
    end

    defmodule Controller do
      @moduledoc false
      defstruct enabled: true, additional_render_functions: []
    end

    defmodule Telemetry do
      @moduledoc false
      defstruct enabled: true, additional_modules: []
    end

    defmodule Database do
      @moduledoc false
      defstruct enabled: true, repo_modules: []
    end

    defmodule LiveView do
      @moduledoc false
      defstruct enabled: true, additional_modules: []
    end

    defstruct logging: nil,
              http: nil,
              controller: nil,
              telemetry: nil,
              database: nil,
              liveview: nil
  end

  defstruct version: 1, pii: [], flows: [], scanners: nil

  @doc false
  def from_map(map) when is_map(map) do
    %__MODULE__{
      version: get(map, :version),
      pii: Enum.map(get(map, :pii) || [], &pii_entry_from_map/1),
      flows: Enum.map(get(map, :flows) || [], &flow_from_map/1),
      scanners: scanners_from_map(get(map, :scanners))
    }
  end

  def default_scanners do
    %Scanners{
      logging: %Logging{},
      http: %HTTP{},
      controller: %Controller{},
      telemetry: %Telemetry{},
      database: %Database{},
      liveview: %LiveView{}
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

  defp scanners_from_map(nil), do: default_scanners()

  defp scanners_from_map(map) when is_map(map) do
    %Scanners{
      logging: logging_scanner_from_map(get(map, :logging)),
      http: http_scanner_from_map(get(map, :http)),
      controller: controller_scanner_from_map(get(map, :controller)),
      telemetry: telemetry_scanner_from_map(get(map, :telemetry)),
      database: database_scanner_from_map(get(map, :database)),
      liveview: liveview_scanner_from_map(get(map, :liveview))
    }
  end

  defp scanners_from_map(_), do: default_scanners()

  defp logging_scanner_from_map(nil), do: %Logging{}

  defp logging_scanner_from_map(map) when is_map(map) do
    %Logging{
      enabled: scanner_enabled(map),
      additional_modules: scanner_list(map, :additional_modules)
    }
  end

  defp logging_scanner_from_map(_), do: %Logging{}

  defp http_scanner_from_map(nil), do: %HTTP{}

  defp http_scanner_from_map(map) when is_map(map) do
    %HTTP{
      enabled: scanner_enabled(map),
      additional_modules: scanner_list(map, :additional_modules),
      internal_domains: scanner_list(map, :internal_domains),
      external_domains: scanner_list(map, :external_domains)
    }
  end

  defp http_scanner_from_map(_), do: %HTTP{}

  defp controller_scanner_from_map(nil), do: %Controller{}

  defp controller_scanner_from_map(map) when is_map(map) do
    %Controller{
      enabled: scanner_enabled(map),
      additional_render_functions: scanner_list(map, :additional_render_functions)
    }
  end

  defp controller_scanner_from_map(_), do: %Controller{}

  defp telemetry_scanner_from_map(nil), do: %Telemetry{}

  defp telemetry_scanner_from_map(map) when is_map(map) do
    %Telemetry{
      enabled: scanner_enabled(map),
      additional_modules: scanner_list(map, :additional_modules)
    }
  end

  defp telemetry_scanner_from_map(_), do: %Telemetry{}

  defp database_scanner_from_map(nil), do: %Database{}

  defp database_scanner_from_map(map) when is_map(map) do
    %Database{
      enabled: scanner_enabled(map),
      repo_modules: scanner_list(map, :repo_modules)
    }
  end

  defp database_scanner_from_map(_), do: %Database{}

  defp liveview_scanner_from_map(nil), do: %LiveView{}

  defp liveview_scanner_from_map(map) when is_map(map) do
    %LiveView{
      enabled: scanner_enabled(map),
      additional_modules: scanner_list(map, :additional_modules)
    }
  end

  defp liveview_scanner_from_map(_), do: %LiveView{}

  defp scanner_enabled(map) do
    case get(map, :enabled) do
      value when is_boolean(value) -> value
      _ -> true
    end
  end

  defp scanner_list(map, key) do
    case get(map, key) do
      list when is_list(list) ->
        Enum.filter(list, &is_binary/1)

      _ ->
        []
    end
  end

  defp get(map, key) when is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
