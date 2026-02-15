defmodule PrivSignal.Scan.Scanner.Cache do
  @moduledoc false

  alias PrivSignal.Scan.Scanner.Utils

  def build(ast, file_path) do
    module_functions = Utils.extract_module_functions(ast)

    alias_map_by_module =
      Enum.reduce(module_functions, %{}, fn module_entry, acc ->
        Map.put(acc, module_entry.module, Utils.extract_alias_map(module_entry))
      end)

    module_classification =
      Enum.reduce(module_functions, %{}, fn module_entry, acc ->
        Map.put(acc, module_entry.module, classify_module(module_entry.module, file_path))
      end)

    %{
      module_functions: module_functions,
      alias_map_by_module: alias_map_by_module,
      module_classification: module_classification
    }
  end

  defp classify_module(module_name, file_path) do
    module_name = to_string(module_name || "")
    file_path = to_string(file_path || "")

    cond do
      String.ends_with?(module_name, "Controller") or String.contains?(file_path, "/controllers/") ->
        :controller

      String.ends_with?(module_name, "Live") or String.ends_with?(module_name, "LiveView") or
          String.contains?(file_path, "/live/") ->
        :liveview

      true ->
        :unknown
    end
  end
end
