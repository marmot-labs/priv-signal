defmodule PrivSignal.Scan.Output.Writer do
  @moduledoc false
  require Logger

  def write(markdown, json, opts \\ []) do
    json_path = Keyword.get(opts, :json_path, "priv-signal-scan.json")
    quiet? = Keyword.get(opts, :quiet, false)
    start = System.monotonic_time()

    Logger.debug("[priv_signal] scan output write starting")

    ensure_directory(json_path)

    unless quiet? do
      IO.puts(markdown)
    end

    result =
      case File.write(json_path, Jason.encode!(json, pretty: true)) do
        :ok ->
          Logger.info("[priv_signal] scan output write ok")
          {:ok, json_path}

        {:error, reason} ->
          Logger.error("[priv_signal] scan output write failed reason=#{inspect(reason)}")
          {:error, reason}
      end

    PrivSignal.Telemetry.emit(
      [:priv_signal, :scan, :output, :write],
      %{duration_ms: duration_ms(start)},
      %{ok: match?({:ok, _}, result), format: :json, scanner_version: scanner_version(json)}
    )

    result
  end

  defp ensure_directory(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  defp scanner_version(json) when is_map(json), do: Map.get(json, :scanner_version) || "unknown"
  defp scanner_version(_), do: "unknown"

  defp duration_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end
end
