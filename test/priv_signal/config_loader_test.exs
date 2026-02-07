defmodule PrivSignal.Config.LoaderTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader

  test "loads config from priv-signal.yml" do
    path = Path.join(System.tmp_dir!(), "priv_signal_#{System.unique_integer([:positive])}.yml")
    File.write!(path, sample_yaml())

    assert {:ok, config} = Loader.load(path)
    assert config.version == 1
    assert length(config.pii) == 2
    assert length(config.flows) == 1
  end

  defp sample_yaml do
    """
    version: 1

    pii:
      - module: MyApp.Accounts.User
        fields:
          - name: email
            category: contact
            sensitivity: medium
      - module: MyApp.Accounts.Author
        fields:
          - name: email
            category: contact
            sensitivity: medium

    flows:
      - id: xapi_export
        description: "User activity exported as xAPI statements"
        purpose: analytics
        pii_categories:
          - user_id
          - ip_address
        path:
          - module: MyAppWeb.ActivityController
            function: submit
          - module: MyApp.Analytics.XAPI
            function: build_statement
        exits_system: true
        third_party: "AWS S3"
    """
  end
end
