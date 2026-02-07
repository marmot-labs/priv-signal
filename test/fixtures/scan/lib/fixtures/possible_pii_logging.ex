defmodule Fixtures.Scan.PossiblePIILogging do
  require Logger

  def log_params(params) do
    Logger.debug(inspect(params))
  end
end
