defmodule PrivSignal.Infer.FlowIdentity do
  @moduledoc """
  Generates stable identity tuples and IDs for inferred privacy flows.
  """

  @stable_prefix "psfs_"
  @variant_prefix "psf_"

  # Stable identity for the logical flow across sink/boundary variants.
  def id(flow) when is_map(flow) do
    flow
    |> stable_identity_tuple()
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
    |> then(&(@stable_prefix <> &1))
  end

  # Variant identity captures the full sink/boundary variant.
  def variant_id(flow) when is_map(flow) do
    flow
    |> variant_identity_tuple()
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
    |> then(&(@variant_prefix <> &1))
  end

  def stable_identity_tuple(flow) when is_map(flow) do
    [
      normalize(Map.get(flow, :source)),
      normalize(Map.get(flow, :source_key)),
      normalize(Map.get(flow, :source_class)),
      normalize(Map.get(flow, :source_sensitive)),
      normalize(Enum.join(Map.get(flow, :linked_refs, []), ",")),
      normalize(Enum.join(Map.get(flow, :linked_classes, []), ",")),
      normalize(Map.get(flow, :entrypoint))
    ]
  end

  def variant_identity_tuple(flow) when is_map(flow) do
    sink = Map.get(flow, :sink, %{})

    stable_identity_tuple(flow) ++
      [
        normalize(Map.get(sink, :kind)),
        normalize(Map.get(sink, :subtype)),
        normalize(Map.get(flow, :boundary))
      ]
  end

  defp normalize(nil), do: ""

  defp normalize(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize()

  defp normalize(value) when is_binary(value) do
    value
    |> String.trim()
  end

  defp normalize(value), do: to_string(value)
end
