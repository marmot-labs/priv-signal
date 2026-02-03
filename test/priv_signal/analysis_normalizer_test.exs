defmodule PrivSignal.Analysis.NormalizerTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Analysis.Normalizer

  test "filters low confidence and deduplicates" do
    payload = %{
      "touched_flows" => [
        %{"flow_id" => "X", "evidence" => "lib/foo.ex:10", "confidence" => 0.9},
        %{"flow_id" => "x", "evidence" => "lib/foo.ex:10", "confidence" => 0.8},
        %{"flow_id" => "y", "evidence" => "lib/foo.ex:11", "confidence" => 0.1}
      ],
      "new_pii" => [],
      "new_sinks" => [],
      "notes" => []
    }

    normalized = Normalizer.normalize(payload, min_confidence: 0.5)

    assert [%{id: "x", evidence: "lib/foo.ex:10"}] = normalized["touched_flows"]
  end
end
