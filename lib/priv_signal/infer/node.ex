defmodule PrivSignal.Infer.Node do
  @moduledoc false

  defstruct id: nil,
            node_type: nil,
            data_refs: [],
            code_context: %{},
            role: %{},
            confidence: nil,
            evidence: []
end
