defmodule PrivSignal.Risk.Assessor do
  @moduledoc false

  alias PrivSignal.Risk.Rules

  def assess(events, opts \\ []) when is_list(events) do
    start = System.monotonic_time()
    {category, reasons} = Rules.categorize(events, opts)

    result = %{
      category: category,
      reasons: reasons,
      events: events
    }

    PrivSignal.Telemetry.emit(
      [:priv_signal, :risk, :assess],
      %{duration_ms: duration_ms(start)},
      %{category: category}
    )

    result
  end

  defp duration_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end
end
