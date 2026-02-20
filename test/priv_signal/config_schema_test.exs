defmodule PrivSignal.Config.SchemaTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Schema

  test "validates a well-formed config" do
    map = %{
      "version" => 1,
      "prd_nodes" => [
        %{
          "key" => "user_email",
          "label" => "User Email",
          "class" => "direct_identifier",
          "sensitive" => true,
          "scope" => %{"module" => "MyApp.Accounts.User", "field" => "email"}
        }
      ],
      "flows" => [
        %{
          "id" => "xapi_export",
          "description" => "User activity exported as xAPI statements",
          "purpose" => "analytics",
          "pii_categories" => ["user_id"],
          "path" => [
            %{"module" => "MyAppWeb.ActivityController", "function" => "submit"}
          ],
          "exits_system" => true,
          "third_party" => "AWS S3"
        }
      ]
    }

    assert {:ok, config} = Schema.validate(map)
    assert config.version == 1
    assert length(config.prd_nodes) == 1
    assert length(config.flows) == 1
  end

  test "returns errors for missing fields" do
    assert {:error, errors} = Schema.validate(%{})
    assert "version is required" in errors
    assert "prd_nodes is required" in errors
    assert "flows is required" in errors
  end

  test "allows missing flows in score mode" do
    map = %{
      "version" => 1,
      "prd_nodes" => []
    }

    assert {:ok, config} = Schema.validate(map, mode: :score)
    assert config.flows == []
  end

  test "rejects deprecated pii_modules key" do
    map = %{
      "version" => 1,
      "pii_modules" => ["MyApp.Accounts.User"],
      "prd_nodes" => [],
      "flows" => []
    }

    assert {:error, errors} = Schema.validate(map)

    assert Enum.any?(
             errors,
             &String.contains?(&1, "pii_modules is unsupported")
           )
  end

  test "accepts scoring config overrides" do
    map = %{
      "version" => 1,
      "prd_nodes" => [
        %{
          "key" => "user_email",
          "label" => "User Email",
          "class" => "direct_identifier",
          "sensitive" => true,
          "scope" => %{"module" => "MyApp.Accounts.User", "field" => "email"}
        }
      ],
      "flows" => [],
      "scoring" => %{
        "weights" => %{"R-HIGH-EXTERNAL-SINK-ADDED" => 7},
        "thresholds" => %{"low_max" => 2, "medium_max" => 6, "high_min" => 7},
        "llm_interpretation" => %{
          "enabled" => false,
          "model" => "gpt-5-mini",
          "timeout_ms" => 5000
        }
      }
    }

    assert {:ok, config} = Schema.validate(map)
    assert config.scoring.weights.values["R-HIGH-EXTERNAL-SINK-ADDED"] == 7
    assert config.scoring.thresholds.low_max == 2
    assert config.scoring.llm_interpretation.model == "gpt-5-mini"
  end

  test "rejects invalid scoring threshold ordering" do
    map = %{
      "version" => 1,
      "prd_nodes" => [
        %{
          "key" => "user_email",
          "label" => "User Email",
          "class" => "direct_identifier",
          "sensitive" => true,
          "scope" => %{"module" => "MyApp.Accounts.User", "field" => "email"}
        }
      ],
      "flows" => [],
      "scoring" => %{
        "thresholds" => %{"low_max" => 5, "medium_max" => 4, "high_min" => 9}
      }
    }

    assert {:error, errors} = Schema.validate(map)

    assert "scoring.thresholds must satisfy low_max < medium_max < high_min" in errors
  end
end
