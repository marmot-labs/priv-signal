defmodule PrivSignal.Config.SchemaTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Schema

  test "validates a well-formed config" do
    map = %{
      "version" => 1,
      "pii" => [
        %{
          "module" => "MyApp.Accounts.User",
          "fields" => [
            %{"name" => "email", "category" => "contact", "sensitivity" => "medium"}
          ]
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
    assert length(config.pii) == 1
    assert length(config.flows) == 1
  end

  test "returns errors for missing fields" do
    assert {:error, errors} = Schema.validate(%{})
    assert "version is required" in errors
    assert "pii is required" in errors
    assert "flows is required" in errors
  end

  test "rejects deprecated pii_modules key" do
    map = %{
      "version" => 1,
      "pii_modules" => ["MyApp.Accounts.User"],
      "pii" => [
        %{
          "module" => "MyApp.Accounts.User",
          "fields" => [
            %{"name" => "email", "category" => "contact", "sensitivity" => "medium"}
          ]
        }
      ],
      "flows" => []
    }

    assert {:error, errors} = Schema.validate(map)

    assert Enum.any?(
             errors,
             &String.contains?(&1, "pii_modules is deprecated")
           )
  end
end
