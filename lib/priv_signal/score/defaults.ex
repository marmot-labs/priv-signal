defmodule PrivSignal.Score.Defaults do
  @moduledoc false

  @weights %{
    "R-HIGH-EXTERNAL-FLOW-ADDED" => 6,
    "R-MEDIUM-INTERNAL-FLOW-ADDED" => 2,
    "R-LOW-FLOW-REMOVED" => 1,
    "R-LOW-CONFIDENCE-ONLY" => 1,
    "R-HIGH-EXTERNAL-SINK-ADDED" => 6,
    "R-HIGH-EXTERNAL-SINK-CHANGED" => 5,
    "R-HIGH-BOUNDARY-EXITS-SYSTEM" => 5,
    "R-LOW-BOUNDARY-INTERNALIZED" => 1,
    "R-HIGH-PII-EXPANDED-HIGH-SENSITIVITY" => 4,
    "R-MEDIUM-PII-EXPANDED" => 3,
    "R-LOW-PII-REDUCED" => 0,
    "R-LOW-DEFAULT" => 1
  }

  @thresholds %{
    low_max: 3,
    medium_max: 8,
    high_min: 9
  }

  @llm_interpretation %{
    enabled: false,
    model: "gpt-5",
    timeout_ms: 8_000,
    retries: 1
  }

  def weights, do: @weights
  def thresholds, do: @thresholds
  def llm_interpretation, do: @llm_interpretation
end
