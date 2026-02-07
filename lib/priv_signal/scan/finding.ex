defmodule PrivSignal.Scan.Finding do
  @moduledoc false

  defstruct id: nil,
            classification: nil,
            confidence: nil,
            sensitivity: nil,
            module: nil,
            function: nil,
            arity: nil,
            file: nil,
            line: nil,
            sink: nil,
            matched_fields: [],
            evidence: []
end
