defmodule PrivSignal.Infer.Node do
  @moduledoc """
  Struct representing a normalized privacy-relevant source, sink, or boundary node.
  """

  defstruct id: nil,
            node_type: nil,
            data_refs: [],
            code_context: %{},
            role: %{},
            confidence: nil,
            evidence: []
end
