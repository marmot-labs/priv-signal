defmodule PrivSignal.Scan.Finding do
  @moduledoc false

  defstruct id: nil,
            classification: nil,
            confidence: nil,
            confidence_hint: nil,
            sensitivity: nil,
            data_classes: [],
            module: nil,
            function: nil,
            arity: nil,
            file: nil,
            line: nil,
            node_type_hint: nil,
            role_kind: nil,
            role_subtype: nil,
            boundary: nil,
            sink: nil,
            matched_nodes: [],
            matched_fields: [],
            evidence: []
end
