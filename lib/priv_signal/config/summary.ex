defmodule PrivSignal.Config.Summary do
  @moduledoc false

  alias PrivSignal.Config

  def build(%Config{} = config) do
    %{
      version: config.version,
      pii_modules: config.pii_modules,
      flows: Enum.map(config.flows, &flow_summary/1)
    }
  end

  defp flow_summary(flow) do
    %{
      id: flow.id,
      description: flow.description,
      purpose: flow.purpose,
      pii_categories: flow.pii_categories,
      exits_system: flow.exits_system,
      third_party: flow.third_party,
      path: Enum.map(flow.path, &path_summary/1)
    }
  end

  defp path_summary(step) do
    %{
      module: step.module,
      function: step.function
    }
  end
end
