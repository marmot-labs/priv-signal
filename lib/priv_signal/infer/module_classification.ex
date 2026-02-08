defmodule PrivSignal.Infer.ModuleClassification do
  @moduledoc false

  defstruct kind: nil,
            confidence: nil,
            evidence_signals: []
end
