defmodule PrivSignal.Score.ConfigOverridesTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Schema
  alias PrivSignal.Score.Engine

  test "applies custom rule weight overrides" do
    map = %{
      "version" => 1,
      "pii" => [
        %{
          "module" => "MyApp.User",
          "fields" => [%{"name" => "email", "category" => "contact", "sensitivity" => "medium"}]
        }
      ],
      "flows" => [],
      "scoring" => %{
        "weights" => %{"R-HIGH-EXTERNAL-SINK-ADDED" => 2},
        "thresholds" => %{"low_max" => 3, "medium_max" => 5, "high_min" => 6}
      }
    }

    assert {:ok, config} = Schema.validate(map)

    diff = %{
      changes: [
        %{
          type: "flow_changed",
          flow_id: "payments",
          change: "external_sink_added",
          severity: "high",
          rule_id: "R-HIGH-EXTERNAL-SINK-ADDED",
          details: %{}
        }
      ]
    }

    assert {:ok, report} = Engine.run(diff, config.scoring)
    assert report.points == 2
    assert report.score == "HIGH"
  end
end
