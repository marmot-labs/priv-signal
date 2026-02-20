defmodule PrivSignal.Config do
  @moduledoc """
  In-memory representation of priv-signal.yml.
  """

  alias PrivSignal.Config.{
    PRDNode,
    PRDScope,
    Scoring,
    Scoring.LLMInterpretation,
    Scoring.Thresholds,
    Scoring.Weights,
    Scanners,
    Scanners.Controller,
    Scanners.Database,
    Scanners.HTTP,
    Scanners.LiveView,
    Scanners.Logging,
    Scanners.Telemetry
  }

  defmodule PRDScope do
    @moduledoc false
    defstruct module: nil, field: nil
  end

  defmodule PRDNode do
    @moduledoc false
    defstruct key: nil,
              label: nil,
              class: nil,
              sensitive: false,
              scope: nil
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

  defmodule Scoring do
    @moduledoc false

    defmodule Weights do
      @moduledoc false
      defstruct values: %{}
    end

    defmodule Thresholds do
      @moduledoc false
      defstruct low_max: 3, medium_max: 8, high_min: 9
    end

    defmodule LLMInterpretation do
      @moduledoc false
      defstruct enabled: false, model: "gpt-5", timeout_ms: 8_000, retries: 1
    end

    defstruct weights: nil, thresholds: nil, llm_interpretation: nil
  end

  defstruct version: 1, prd_nodes: [], scanners: nil, scoring: nil

  @doc false
  def from_map(map) when is_map(map) do
    prd_nodes = Enum.map(get(map, :prd_nodes) || [], &prd_node_from_map/1)

    %__MODULE__{
      version: get(map, :version),
      prd_nodes: prd_nodes,
      scanners: scanners_from_map(get(map, :scanners)),
      scoring: scoring_from_map(get(map, :scoring))
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

  def default_scoring do
    defaults = PrivSignal.Score.Defaults

    %Scoring{
      weights: %Weights{values: defaults.weights()},
      thresholds: %Thresholds{
        low_max: defaults.thresholds().low_max,
        medium_max: defaults.thresholds().medium_max,
        high_min: defaults.thresholds().high_min
      },
      llm_interpretation: %LLMInterpretation{
        enabled: defaults.llm_interpretation().enabled,
        model: defaults.llm_interpretation().model,
        timeout_ms: defaults.llm_interpretation().timeout_ms,
        retries: defaults.llm_interpretation().retries
      }
    }
  end

  defp prd_node_from_map(map) do
    %PRDNode{
      key: get(map, :key),
      label: get(map, :label),
      class: get(map, :class),
      sensitive: get(map, :sensitive) || false,
      scope: prd_scope_from_map(get(map, :scope))
    }
  end

  defp prd_scope_from_map(map) when is_map(map) do
    %PRDScope{
      module: get(map, :module),
      field: get(map, :field)
    }
  end

  defp prd_scope_from_map(_), do: nil

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

  defp scoring_from_map(nil), do: default_scoring()

  defp scoring_from_map(map) when is_map(map) do
    defaults = default_scoring()
    weights = get(map, :weights) || %{}
    thresholds = get(map, :thresholds) || %{}
    llm = get(map, :llm_interpretation) || %{}

    %Scoring{
      weights: %Weights{values: Map.merge(defaults.weights.values, stringify_keys(weights))},
      thresholds: %Thresholds{
        low_max: get(thresholds, :low_max) || defaults.thresholds.low_max,
        medium_max: get(thresholds, :medium_max) || defaults.thresholds.medium_max,
        high_min: get(thresholds, :high_min) || defaults.thresholds.high_min
      },
      llm_interpretation: %LLMInterpretation{
        enabled: get(llm, :enabled) || defaults.llm_interpretation.enabled,
        model: get(llm, :model) || defaults.llm_interpretation.model,
        timeout_ms: get(llm, :timeout_ms) || defaults.llm_interpretation.timeout_ms,
        retries: get(llm, :retries) || defaults.llm_interpretation.retries
      }
    }
  end

  defp scoring_from_map(_), do: default_scoring()

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

  defp stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      {normalized_key, value}
    end)
  end
end
