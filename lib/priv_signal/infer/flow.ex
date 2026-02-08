defmodule PrivSignal.Infer.Flow do
  @moduledoc false

  defstruct id: nil,
            source: nil,
            entrypoint: nil,
            sink: %{},
            boundary: nil,
            confidence: nil,
            evidence: []
end
