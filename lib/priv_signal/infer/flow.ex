defmodule PrivSignal.Infer.Flow do
  @moduledoc false

  defstruct id: nil,
            source: nil,
            source_key: nil,
            source_class: nil,
            source_sensitive: false,
            linked_refs: [],
            linked_classes: [],
            entrypoint: nil,
            sink: %{},
            boundary: nil,
            confidence: nil,
            evidence: []
end
