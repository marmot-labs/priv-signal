defmodule PrivSignal.Scan.Evidence do
  @moduledoc """
  Struct representing symbol-level evidence that links code to PRD nodes.
  """

  defstruct type: nil,
            expression: nil,
            fields: [],
            match_source: nil,
            lineage: []
end
