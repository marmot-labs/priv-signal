defmodule PrivSignal.Infer.NodeNormalizer do
  @moduledoc false

  alias PrivSignal.Infer.{EvidenceSignal, Node}

  def normalize(node, opts \\ [])

  def normalize(node, opts) when is_map(node) do
    root = Keyword.get(opts, :root, File.cwd!())

    %Node{
      id: get(node, :id),
      node_type: normalize_node_type(get(node, :node_type)),
      pii: normalize_pii(get(node, :pii)),
      code_context: normalize_code_context(get(node, :code_context), root),
      role: normalize_role(get(node, :role)),
      confidence: normalize_confidence(get(node, :confidence)),
      evidence: normalize_evidence(get(node, :evidence))
    }
  end

  def normalize(_node, _opts), do: %Node{}

  def sort_key(node) do
    normalized = normalize(node)

    {
      to_string(normalized.id || ""),
      normalized.node_type || "",
      get_in(normalized.code_context, [:module]) || "",
      get_in(normalized.code_context, [:function]) || "",
      get_in(normalized.code_context, [:file_path]) || "",
      get_in(normalized.role, [:kind]) || "",
      normalized
      |> Map.get(:pii, [])
      |> Enum.map(&Map.get(&1, :reference))
      |> Enum.reject(&is_nil/1)
      |> Enum.join(",")
    }
  end

  def canonical_file_path(path, root \\ File.cwd!())

  def canonical_file_path(nil, _root), do: nil

  def canonical_file_path(path, root) when is_binary(path) do
    normalized_path = String.replace(path, "\\", "/")
    normalized_root = String.replace(root, "\\", "/")

    case Path.type(normalized_path) do
      :absolute ->
        case Path.relative_to(normalized_path, normalized_root) do
          relative when relative == normalized_path -> normalized_path
          relative -> relative
        end

      :relative ->
        normalized_path
    end
  end

  def canonical_file_path(path, _root), do: path

  def canonical_module_name(nil), do: nil

  def canonical_module_name(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> canonical_module_name()
  end

  def canonical_module_name(module) when is_binary(module) do
    module
    |> String.trim()
    |> case do
      "" -> nil
      "Elixir." <> rest -> rest
      value -> value
    end
  end

  def canonical_module_name(_), do: nil

  def canonical_function_name(nil), do: nil

  def canonical_function_name(function) when is_atom(function) do
    function
    |> Atom.to_string()
    |> canonical_function_name()
  end

  def canonical_function_name(function) when is_binary(function) do
    function
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  def canonical_function_name(_), do: nil

  defp normalize_node_type(node_type) when is_atom(node_type) and not is_nil(node_type) do
    node_type
    |> Atom.to_string()
    |> normalize_node_type()
  end

  defp normalize_node_type(node_type) when is_binary(node_type) do
    node_type
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_node_type(_), do: nil

  defp normalize_pii(pii) when is_list(pii) do
    pii
    |> Enum.map(fn pii_entry ->
      %{
        reference: normalize_reference(get(pii_entry, :reference) || get(pii_entry, :ref)),
        category: normalize_value(get(pii_entry, :category)),
        sensitivity: normalize_value(get(pii_entry, :sensitivity))
      }
    end)
    |> Enum.reject(&is_nil(&1.reference))
    |> Enum.uniq_by(&{&1.reference, &1.category, &1.sensitivity})
    |> Enum.sort_by(&{&1.reference, &1.category || "", &1.sensitivity || ""})
  end

  defp normalize_pii(_), do: []

  defp normalize_reference(nil), do: nil

  defp normalize_reference(reference) when is_atom(reference) do
    reference
    |> Atom.to_string()
    |> normalize_reference()
  end

  defp normalize_reference(reference) when is_binary(reference) do
    reference
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_reference(_), do: nil

  defp normalize_code_context(context, root) when is_map(context) do
    base = %{
      module: canonical_module_name(get(context, :module)),
      function: canonical_function_name(get(context, :function)),
      file_path: canonical_file_path(get(context, :file_path), root)
    }

    case normalize_lines(get(context, :lines)) do
      [] -> base
      lines -> Map.put(base, :lines, lines)
    end
  end

  defp normalize_code_context(_context, _root) do
    %{module: nil, function: nil, file_path: nil}
  end

  defp normalize_lines(lines) when is_list(lines) do
    lines
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_lines(_), do: []

  defp normalize_role(role) when is_map(role) do
    kind = role |> get(:kind) |> normalize_value() |> normalize_lowercase()
    callee = role |> get(:callee) |> normalize_value()
    arity = normalize_arity(role |> get(:arity))

    base = %{kind: kind, callee: callee}

    case arity do
      nil -> base
      value -> Map.put(base, :arity, value)
    end
  end

  defp normalize_role(_), do: %{kind: nil, callee: nil}

  defp normalize_confidence(value) when is_number(value), do: value

  defp normalize_confidence(:confirmed), do: 1.0
  defp normalize_confidence(:possible), do: 0.7
  defp normalize_confidence(_), do: 0.5

  defp normalize_evidence(evidence) when is_list(evidence) do
    evidence
    |> Enum.map(fn entry ->
      %EvidenceSignal{
        rule: normalize_value(get(entry, :rule)),
        signal: normalize_value(get(entry, :signal)),
        finding_id: normalize_value(get(entry, :finding_id)),
        line: normalize_line(get(entry, :line)),
        ast_kind: normalize_value(get(entry, :ast_kind))
      }
    end)
    |> Enum.uniq_by(&{&1.rule, &1.signal, &1.finding_id, &1.line, &1.ast_kind})
    |> Enum.sort_by(
      &{&1.rule || "", &1.signal || "", &1.finding_id || "", &1.line || 0, &1.ast_kind || ""}
    )
  end

  defp normalize_evidence(_), do: []

  defp normalize_line(line) when is_integer(line), do: line
  defp normalize_line(_), do: nil

  defp normalize_arity(nil), do: nil
  defp normalize_arity(arity) when is_integer(arity) and arity >= 0, do: arity
  defp normalize_arity(_), do: nil

  defp normalize_value(nil), do: nil

  defp normalize_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_value(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_value()

  defp normalize_value(value), do: to_string(value)

  defp normalize_lowercase(nil), do: nil
  defp normalize_lowercase(value), do: String.downcase(value)

  defp get(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
