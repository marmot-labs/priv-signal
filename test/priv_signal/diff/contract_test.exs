defmodule PrivSignal.Diff.ContractTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Diff.Contract
  alias PrivSignal.Test.DiffFixtureHelper

  test "validates artifact and returns warnings for missing optional sections in non-strict mode" do
    artifact = %{
      "schema_version" => "1.2",
      "flows" => [
        %{
          "id" => "flow_1",
          "source" => "Demo.User.email",
          "entrypoint" => "DemoWeb.UserController.create/2",
          "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
          "boundary" => "internal"
        }
      ]
    }

    assert {:ok, validated} = Contract.validate(artifact, strict: false)
    assert validated.schema_version == "1.2"
    assert is_list(validated.warnings)
    assert Enum.any?(validated.warnings, &String.contains?(&1, "optional section missing"))
  end

  test "strict mode fails when optional sections are missing" do
    artifact = %{
      "schema_version" => "1.2",
      "flows" => [
        %{
          "id" => "flow_1",
          "source" => "Demo.User.email",
          "entrypoint" => "DemoWeb.UserController.create/2",
          "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
          "boundary" => "internal"
        }
      ]
    }

    assert {:error, {:missing_optional_sections, %{paths: paths}}} =
             Contract.validate(artifact, strict: true)

    assert "nodes" in paths
    assert "flows[0].confidence" in paths
    assert "flows[0].evidence" in paths
  end

  test "returns unsupported schema version error" do
    artifact =
      DiffFixtureHelper.build_artifact([
        %{
          "id" => "flow_1",
          "source" => "Demo.User.email",
          "entrypoint" => "DemoWeb.UserController.create/2",
          "sink" => %{"kind" => "logger", "subtype" => "Logger.info"},
          "boundary" => "internal"
        }
      ])
      |> Map.put("schema_version", "2.0")

    assert {:error, {:unsupported_schema_version, %{schema_version: "2.0", supported: supported}}} =
             Contract.validate(artifact, strict: false)

    assert "1.2" in supported
  end

  test "returns missing required keys for flow" do
    artifact = %{
      "schema_version" => "1.2",
      "flows" => [
        %{
          "id" => "flow_1",
          "source" => "Demo.User.email"
        }
      ],
      "nodes" => []
    }

    assert {:error, {:missing_required_keys, %{scope: {:flow, 0}, keys: keys}}} =
             Contract.validate(artifact, strict: false)

    assert "entrypoint" in keys
    assert "sink" in keys
    assert "boundary" in keys
  end
end
