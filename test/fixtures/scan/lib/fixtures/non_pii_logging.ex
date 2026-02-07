defmodule Fixtures.Scan.NonPIILogging do
  require Logger

  def log_system_state(state) do
    Logger.info("state=#{state}")
  end
end
