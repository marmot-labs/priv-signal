defmodule Fixtures.Scan.ConfirmedPIILogging do
  require Logger

  def log_user_email(user) do
    Logger.info("user_email=#{user.email}")
  end
end
