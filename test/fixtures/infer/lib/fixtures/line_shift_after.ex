defmodule Fixtures.LineShiftAfter do
  require Logger

  # Non-semantic extra line to shift evidence line numbers.
  def log_user(user) do
    Logger.info("created user", email: user.email)
  end
end
