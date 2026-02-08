defmodule Fixtures.LineShiftBefore do
  require Logger

  def log_user(user) do
    Logger.info("created user", email: user.email)
  end
end
