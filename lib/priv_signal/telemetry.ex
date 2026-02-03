defmodule PrivSignal.Telemetry do
  @moduledoc false

  def emit(event, measurements, metadata \\ %{}) when is_list(event) do
    :telemetry.execute(event, measurements, metadata)
  end
end
