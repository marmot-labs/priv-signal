defmodule Mix.Tasks.PrivSignal.Init do
  use Mix.Task

  @shortdoc "Create a starter priv-signal.yml"

  @moduledoc """
  Creates a starter priv-signal.yml in the current directory.
  """

  @impl true
  def run(_args) do
    path = PrivSignal.config_path()

    if File.exists?(path) do
      Mix.shell().info("priv-signal.yml already exists at #{path}")
    else
      File.write!(path, sample_config())
      Mix.shell().info("Created #{path}")
    end
  end

  defp sample_config do
    """
    version: 1

    pii:
      - module: MyApp.Accounts.User
        fields:
          - name: email
            category: contact
            sensitivity: medium
          - name: user_id
            category: identifier
            sensitivity: low

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
          - module: MyApp.Storage.S3
            function: put_object
        exits_system: true
        third_party: "AWS S3"
    """
  end
end
