defmodule PrivSignal.Infer.FlowScorer do
  @moduledoc false

  @default_weights %{
    same_function_context: 0.5,
    direct_reference: 0.2,
    possible_pii_penalty: -0.2,
    indirect_only_penalty: -0.2
  }

  def score(signals, opts \\ [])

  def score(signals, opts) when is_map(signals) do
    weights = Keyword.get(opts, :weights, @default_weights)

    total =
      0.0 +
        maybe(signals[:same_function_context], weights[:same_function_context]) +
        maybe(signals[:direct_reference], weights[:direct_reference]) +
        maybe(signals[:possible_pii], weights[:possible_pii_penalty]) +
        maybe(signals[:indirect_only], weights[:indirect_only_penalty])

    total
    |> clamp()
    |> round_to_2()
  end

  def score(_signals, _opts), do: 0.0

  defp maybe(true, weight) when is_number(weight), do: weight
  defp maybe(_flag, _weight), do: 0.0

  defp clamp(value) when value < 0.0, do: 0.0
  defp clamp(value) when value > 1.0, do: 1.0
  defp clamp(value), do: value

  defp round_to_2(value), do: Float.round(value, 2)
end
