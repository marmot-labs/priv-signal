defmodule PrivSignal.ConfigSchemaScannersTest do
  use ExUnit.Case, async: true

  @fixture_root Path.expand("../fixtures/sinks/config", __DIR__)

  test "fixture config without scanners remains schema-valid and injects defaults" do
    assert {:ok, config_map} = YamlElixir.read_from_file(fixture_path("valid_sinks_pii.yml"))
    assert {:ok, config} = PrivSignal.Config.Schema.validate(config_map)

    assert is_struct(config.scanners, PrivSignal.Config.Scanners)
    assert config.scanners.logging.enabled
    assert config.scanners.http.enabled
    assert config.scanners.controller.enabled
    assert config.scanners.telemetry.enabled
    assert config.scanners.database.enabled
    assert config.scanners.liveview.enabled
  end

  test "accepts explicit scanners configuration" do
    config = %{
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
          "id" => "f1",
          "description" => "d",
          "purpose" => "p",
          "pii_categories" => ["contact"],
          "path" => [%{"module" => "MyApp.Accounts", "function" => "update_user"}],
          "exits_system" => false
        }
      ],
      "scanners" => %{
        "logging" => %{"enabled" => true, "additional_modules" => ["MyApp.Logging"]},
        "http" => %{
          "enabled" => true,
          "additional_modules" => ["MyApp.HTTP"],
          "internal_domains" => ["internal.myapp.com"],
          "external_domains" => ["api.segment.io"]
        },
        "controller" => %{
          "enabled" => true,
          "additional_render_functions" => ["MyAppWeb.API.render_json"]
        },
        "telemetry" => %{"enabled" => false, "additional_modules" => ["MyApp.Analytics"]},
        "database" => %{"enabled" => true, "repo_modules" => ["MyApp.Repo"]},
        "liveview" => %{"enabled" => true, "additional_modules" => ["MyAppWeb.CustomLive"]}
      }
    }

    assert {:ok, parsed} = PrivSignal.Config.Schema.validate(config)

    assert parsed.scanners.logging.additional_modules == ["MyApp.Logging"]
    assert parsed.scanners.http.additional_modules == ["MyApp.HTTP"]
    assert parsed.scanners.http.internal_domains == ["internal.myapp.com"]
    assert parsed.scanners.telemetry.enabled == false
    assert parsed.scanners.database.repo_modules == ["MyApp.Repo"]
  end

  test "rejects malformed scanners configuration" do
    config = %{
      "version" => 1,
      "pii" => [
        %{
          "module" => "MyApp.Accounts.User",
          "fields" => [
            %{"name" => "email", "category" => "contact", "sensitivity" => "medium"}
          ]
        }
      ],
      "flows" => [],
      "scanners" => %{
        "logging" => %{"enabled" => "yes", "additional_modules" => "MyApp.Logging"},
        "http" => %{"enabled" => "yes", "additional_modules" => "MyApp.HTTP"},
        "controller" => %{"additional_render_functions" => [123]},
        "unknown" => %{"enabled" => true}
      }
    }

    assert {:error, errors} = PrivSignal.Config.Schema.validate(config)

    assert "scanners.logging.enabled must be a boolean" in errors
    assert "scanners.logging.additional_modules must be a list of strings" in errors
    assert "scanners.http.enabled must be a boolean" in errors
    assert "scanners.http.additional_modules must be a list of strings" in errors
    assert "scanners.controller.additional_render_functions must be a list of strings" in errors
    assert "scanners.unknown is not a supported scanner category" in errors
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
