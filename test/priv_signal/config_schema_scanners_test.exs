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
      "prd_nodes" => [
        %{
          "key" => "user_email",
          "label" => "User Email",
          "class" => "direct_identifier",
          "sensitive" => true,
          "scope" => %{"module" => "MyApp.Accounts.User", "field" => "email"}
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
        "database" => %{
          "enabled" => true,
          "repo_modules" => ["MyApp.Repo"],
          "wrapper_modules" => ["MyApp.Persistence"],
          "wrapper_functions" => ["append_step/2"]
        },
        "liveview" => %{"enabled" => true, "additional_modules" => ["MyAppWeb.CustomLive"]}
      },
      "matching" => %{
        "aliases" => %{"invitee_email" => "email"},
        "split_case" => true,
        "singularize" => true,
        "strip_prefixes" => ["submitted", "invitee"]
      },
      "strict_exact_only" => false
    }

    assert {:ok, parsed} = PrivSignal.Config.Schema.validate(config)

    assert parsed.scanners.logging.additional_modules == ["MyApp.Logging"]
    assert parsed.scanners.http.additional_modules == ["MyApp.HTTP"]
    assert parsed.scanners.http.internal_domains == ["internal.myapp.com"]
    assert parsed.scanners.telemetry.enabled == false
    assert parsed.scanners.database.repo_modules == ["MyApp.Repo"]
    assert parsed.scanners.database.wrapper_modules == ["MyApp.Persistence"]
    assert parsed.scanners.database.wrapper_functions == ["append_step/2"]
    assert parsed.matching.aliases == %{"invitee_email" => "email"}
    assert parsed.matching.strip_prefixes == ["submitted", "invitee"]
    assert parsed.strict_exact_only == false
  end

  test "rejects malformed scanners configuration" do
    config = %{
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
      "scanners" => %{
        "logging" => %{"enabled" => "yes", "additional_modules" => "MyApp.Logging"},
        "http" => %{"enabled" => "yes", "additional_modules" => "MyApp.HTTP"},
        "controller" => %{"additional_render_functions" => [123]},
        "database" => %{"wrapper_modules" => "MyApp.Persistence"},
        "unknown" => %{"enabled" => true}
      },
      "matching" => %{
        "aliases" => %{"bad" => 12},
        "split_case" => "yes"
      },
      "strict_exact_only" => "no"
    }

    assert {:error, errors} = PrivSignal.Config.Schema.validate(config)

    assert "scanners.logging.enabled must be a boolean" in errors
    assert "scanners.logging.additional_modules must be a list of strings" in errors
    assert "scanners.http.enabled must be a boolean" in errors
    assert "scanners.http.additional_modules must be a list of strings" in errors
    assert "scanners.controller.additional_render_functions must be a list of strings" in errors
    assert "scanners.database.wrapper_modules must be a list of strings" in errors
    assert "matching.aliases values must be non-empty strings" in errors
    assert "matching.split_case must be a boolean" in errors
    assert "strict_exact_only must be a boolean" in errors
    assert "scanners.unknown is not a supported scanner category" in errors
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)
end
