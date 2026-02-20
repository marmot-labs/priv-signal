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

    prd_nodes:
      - key: user_email
        label: User Email
        class: direct_identifier
        sensitive: true
        scope:
          module: MyApp.Accounts.User
          field: email
      - key: user_id
        label: User ID
        class: persistent_pseudonymous_identifier
        sensitive: false
        scope:
          module: MyApp.Accounts.User
          field: user_id
      - key: session_seconds
        label: Session Duration Seconds
        class: behavioral_signal
        sensitive: false
        scope:
          module: MyApp.Analytics.SessionEvent
          field: duration_seconds
      - key: engagement_score
        label: Engagement Score
        class: inferred_attribute
        sensitive: false
        scope:
          module: MyApp.Analytics.UserProfile
          field: engagement_score
      - key: mental_health_category
        label: Mental Health Category
        class: sensitive_context_indicator
        sensitive: true
        scope:
          module: MyApp.Health.Profile
          field: mental_health_category

    scanners:
      logging:
        enabled: true
        additional_modules: []
      http:
        enabled: true
        additional_modules: []
        internal_domains: []
        external_domains: []
      controller:
        enabled: true
        additional_render_functions: []
      telemetry:
        enabled: true
        additional_modules: []
      database:
        enabled: true
        repo_modules: []
      liveview:
        enabled: true
        additional_modules: []
    """
  end
end
