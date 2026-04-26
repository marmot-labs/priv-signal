defmodule PrivSignal.Infer.Flow do
  @moduledoc """
  Struct representing a privacy-relevant flow captured in the lockfile.
  """

  defstruct id: nil,
            stable_id: nil,
            variant_id: nil,
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
