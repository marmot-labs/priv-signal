defmodule PrivSignal.Telemetry do
  @moduledoc """
  Provides a small wrapper for emitting PrivSignal telemetry events.
  """

  def emit(event, measurements, metadata \\ %{}) when is_list(event) do
    :telemetry.execute(event, measurements, metadata)
  end
end
