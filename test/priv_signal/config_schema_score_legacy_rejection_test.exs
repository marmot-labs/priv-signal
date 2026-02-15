defmodule PrivSignal.ConfigSchemaScoreLegacyRejectionTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Schema

  test "rejects legacy scoring.weights and scoring.thresholds in score mode" do
    map = %{
      "version" => 1,
      "pii" => [
        %{
          "module" => "Demo.User",
          "fields" => [%{"name" => "email", "category" => "contact", "sensitivity" => "medium"}]
        }
      ],
      "scoring" => %{
        "weights" => %{"R-HIGH-EXTERNAL-SINK-ADDED" => 8},
        "thresholds" => %{"low_max" => 2, "medium_max" => 4, "high_min" => 6}
      }
    }

    assert {:error, errors} = Schema.validate(map, mode: :score)
    assert "scoring.weights is unsupported for score v2" in errors
    assert "scoring.thresholds is unsupported for score v2" in errors
  end
end
