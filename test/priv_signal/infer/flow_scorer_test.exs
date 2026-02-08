defmodule PrivSignal.Infer.FlowScorerTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.FlowScorer

  test "scores additive signals with clamping and rounding" do
    assert FlowScorer.score(%{
             same_function_context: true,
             direct_reference: true,
             possible_pii: false,
             indirect_only: false
           }) == 0.7
  end

  test "clamps to 1.0 when score exceeds upper bound" do
    assert FlowScorer.score(
             %{
               same_function_context: true,
               direct_reference: true,
               possible_pii: true,
               indirect_only: true
             },
             weights: %{
               same_function_context: 1.0,
               direct_reference: 0.9,
               possible_pii_penalty: 0.0,
               indirect_only_penalty: 0.0
             }
           ) == 1.0
  end

  test "clamps to 0.0 when penalties push below zero" do
    assert FlowScorer.score(%{
             same_function_context: false,
             direct_reference: false,
             possible_pii: true,
             indirect_only: true
           }) == 0.0
  end
end
