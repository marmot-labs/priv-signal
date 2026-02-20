defmodule PrivSignal.Infer.Output.Markdown do
  @moduledoc false

  def render(result) when is_map(result) do
    summary = Map.get(result, :summary, %{})
    nodes = Map.get(result, :nodes, [])
    errors = Map.get(result, :errors, [])

    lines = [
      "## PrivSignal Scan Lockfile",
      "",
      "**Schema version:** #{Map.get(result, :schema_version, "unknown")}",
      "**Node count:** #{Map.get(summary, :node_count, 0)}",
      "**Flow count:** #{Map.get(summary, :flow_count, 0)}",
      "**Flow hash:** #{Map.get(summary, :flows_hash, "none")}",
      "**Files scanned:** #{Map.get(summary, :files_scanned, 0)}",
      "**Scan errors:** #{Map.get(summary, :scan_error_count, 0)}"
    ]

    lines =
      if nodes == [] do
        lines ++ ["", "No PRD evidence nodes were emitted."]
      else
        lines ++ ["", "**Nodes:**", "" | Enum.map(nodes, &format_node/1)]
      end

    lines =
      if errors == [] do
        lines
      else
        lines ++ ["", "**Operational Errors:**", "" | Enum.map(errors, &format_error/1)]
      end

    Enum.join(lines, "\n")
  end

  defp format_node(node) do
    context = Map.get(node, :code_context, %{})
    role = Map.get(node, :role, %{})

    module = Map.get(context, :module, "unknown")
    function = Map.get(context, :function, "unknown")
    file_path = Map.get(context, :file_path, "unknown")
    kind = Map.get(role, :kind, "unknown")

    "- [#{String.upcase(to_string(Map.get(node, :node_type, "unknown")))}] #{module}.#{function} (#{file_path}) kind=#{kind}"
  end

  defp format_error(error) do
    file = error[:file] || "unknown_file"
    reason = error[:reason] || "unknown_reason"
    "- #{file}: #{reason}"
  end
end
