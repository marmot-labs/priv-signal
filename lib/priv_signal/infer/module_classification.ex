defmodule PrivSignal.Infer.ModuleClassification do
  @moduledoc """
  Struct capturing how a module participates in inferred privacy behavior.
  """

  defstruct kind: nil,
            confidence: nil,
            evidence_signals: []
end
