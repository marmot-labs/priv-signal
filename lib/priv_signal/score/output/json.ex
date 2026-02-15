defmodule PrivSignal.Score.Output.JSON do
  @moduledoc false

  @schema_version "v2"

  def schema_version, do: @schema_version

  def render(report, llm_interpretation \\ nil) when is_map(report) do
    %{
      version: @schema_version,
      score: Map.get(report, :score),
      summary: Map.get(report, :summary, %{}),
      reasons: Map.get(report, :reasons, []),
      llm_interpretation: llm_interpretation
    }
  end
end
