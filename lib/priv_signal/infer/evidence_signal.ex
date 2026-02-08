defmodule PrivSignal.Infer.EvidenceSignal do
  @moduledoc false

  defstruct rule: nil,
            signal: nil,
            finding_id: nil,
            line: nil,
            ast_kind: nil
end
