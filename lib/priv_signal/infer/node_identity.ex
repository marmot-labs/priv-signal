defmodule PrivSignal.Infer.NodeIdentity do
  @moduledoc false

  alias PrivSignal.Infer.NodeNormalizer

  @id_prefix "psn_"

  def id(node, opts \\ []) when is_map(node) do
    node
    |> identity_tuple(opts)
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
    |> then(&(@id_prefix <> &1))
  end

  def identity_tuple(node, opts \\ []) when is_map(node) do
    root = Keyword.get(opts, :root, File.cwd!())
    normalized = NodeNormalizer.normalize(node, root: root)

    [
      normalized.node_type || "",
      normalized.code_context.module || "",
      normalized.code_context.function || "",
      normalized.code_context.file_path || "",
      normalize_role_kind(normalized.role.kind),
      canonical_references(normalized.data_refs)
    ]
  end

  defp normalize_role_kind(kind) when is_atom(kind),
    do: kind |> Atom.to_string() |> normalize_role_kind()

  defp normalize_role_kind(kind) when is_binary(kind) do
    kind
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_role_kind(_), do: ""

  defp canonical_references(data_refs) when is_list(data_refs) do
    data_refs
    |> Enum.map(fn entry ->
      get(entry, :reference)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&normalize_reference/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.sort()
    |> Enum.uniq()
    |> Enum.join(",")
  end

  defp canonical_references(_), do: ""

  defp normalize_reference(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_reference()

  defp normalize_reference(value) when is_binary(value) do
    value
    |> String.trim()
  end

  defp normalize_reference(_), do: ""

  defp get(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
