defmodule Fixtures.TelemetrySink do
  def track(user) do
    :telemetry.execute([:my_app, :user, :tracked], %{count: 1}, %{email: user.email})
  end
end
