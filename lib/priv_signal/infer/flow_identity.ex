defmodule PrivSignal.Infer.FlowIdentity do
  @moduledoc false

  @id_prefix "psf_"

  def id(flow) when is_map(flow) do
    flow
    |> identity_tuple()
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
    |> then(&(@id_prefix <> &1))
  end

  def identity_tuple(flow) when is_map(flow) do
    sink = Map.get(flow, :sink, %{})

    [
      normalize(Map.get(flow, :source)),
      normalize(Map.get(flow, :entrypoint)),
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
