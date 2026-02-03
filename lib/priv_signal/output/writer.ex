defmodule PrivSignal.Output.Writer do
  @moduledoc false

  def write(markdown, json, opts \\ []) do
    output_path = Keyword.get(opts, :json_path, "priv-signal.json")
    quiet? = Keyword.get(opts, :quiet, false)
    start = System.monotonic_time()

    unless quiet? do
      IO.puts(markdown)
    end

    result =
      case File.write(output_path, Jason.encode!(json, pretty: true)) do
        :ok -> {:ok, output_path}
        {:error, reason} -> {:error, reason}
      end

    PrivSignal.Telemetry.emit(
      [:priv_signal, :output, :write],
      %{duration_ms: duration_ms(start)},
      %{path: output_path, ok: match?({:ok, _}, result)}
    )

    result
  end

  defp duration_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end
end
