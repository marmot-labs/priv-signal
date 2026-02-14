defmodule PrivSignal.Infer.Output.Writer do
  @moduledoc false

  require Logger

  def write(markdown, json, opts \\ []) do
    json_path = Keyword.get(opts, :json_path, "priv_signal.lockfile.json")
    quiet? = Keyword.get(opts, :quiet, false)
    start = System.monotonic_time()

    ensure_directory(json_path)

    unless quiet? do
      IO.puts(markdown)
    end

    result =
      case File.write(json_path, Jason.encode!(json, pretty: true)) do
        :ok -> {:ok, json_path}
        {:error, reason} -> {:error, reason}
      end

    PrivSignal.Telemetry.emit(
      [:priv_signal, :infer, :output, :write],
      %{duration_ms: duration_ms(start)},
      %{
        ok: match?({:ok, _}, result),
        format: :json,
        schema_version: schema_version(json)
      }
    )

    case result do
      {:ok, _path} ->
        Logger.info("[priv_signal] infer output write ok")

      {:error, reason} ->
        Logger.error("[priv_signal] infer output write failed reason=#{inspect(reason)}")
    end

    result
  end

  defp ensure_directory(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  defp schema_version(json) when is_map(json), do: Map.get(json, :schema_version) || "unknown"
  defp schema_version(_), do: "unknown"

  defp duration_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end
end
