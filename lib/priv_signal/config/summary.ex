defmodule PrivSignal.Config.Summary do
  @moduledoc false

  alias PrivSignal.Config
  alias PrivSignal.Config.PII

  def build(%Config{} = config) do
    %{
      version: config.version,
      pii: Enum.map(PII.entries(config), &pii_entry_summary/1),
      pii_modules: PII.modules(config),
      scanners: scanners_summary(config),
      flows: Enum.map(config.flows, &flow_summary/1)
    }
  end

  defp pii_entry_summary(entry) do
    %{
      module: entry.module,
      fields: Enum.map(entry.fields || [], &pii_field_summary/1)
    }
  end

  defp pii_field_summary(field) do
    %{
      name: field.name,
      category: field.category,
      sensitivity: field.sensitivity
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

  defp scanners_summary(config) do
    scanners = config.scanners || PrivSignal.Config.default_scanners()

    %{
      logging: scanner_entry_summary(scanners.logging),
      http: scanner_entry_summary(scanners.http),
      controller: scanner_entry_summary(scanners.controller),
      telemetry: scanner_entry_summary(scanners.telemetry),
      database: scanner_entry_summary(scanners.database),
      liveview: scanner_entry_summary(scanners.liveview)
    }
  end

  defp scanner_entry_summary(scanner) when is_map(scanner) do
    scanner
    |> Map.from_struct()
    |> Enum.into(%{}, fn {key, value} ->
      case value do
        list when is_list(list) -> {key, Enum.sort(list)}
        _ -> {key, value}
      end
    end)
  end
end
