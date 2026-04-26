defmodule PrivSignal.Infer.EvidenceSignal do
  @moduledoc """
  Struct describing a single scanner evidence signal used during inference.
  """

  defstruct rule: nil,
            signal: nil,
            finding_id: nil,
            line: nil,
            ast_kind: nil
end
