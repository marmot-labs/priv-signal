defmodule PrivSignal.Config.Loader do
  @moduledoc false

  alias PrivSignal.Config.Schema

  def load(path \\ PrivSignal.config_path(), opts \\ []) do
    start = System.monotonic_time()
    mode = Keyword.get(opts, :mode, :default)

    result =
      with {:ok, raw} <- parse_yaml(path),
           {:ok, config} <- Schema.validate(raw, mode: mode) do
        {:ok, config}
      end

    PrivSignal.Telemetry.emit(
      [:priv_signal, :config, :load],
      %{duration_ms: duration_ms(start)},
      %{path: path, ok: match?({:ok, _}, result), mode: mode}
    )

    result
  end

  defp parse_yaml(path) do
    cond do
      not File.exists?(path) ->
        {:error, "config not found: #{path}"}

      Code.ensure_loaded?(YamlElixir) ->
        read_yaml(path)

      true ->
        {:error, "YamlElixir not available; add :yaml_elixir dependency"}
    end
  end

  defp read_yaml(path) do
    try do
      case apply(YamlElixir, :read_from_file, [path]) do
        {:ok, map} when is_map(map) -> {:ok, map}
        {:error, reason} -> {:error, reason}
        map when is_map(map) -> {:ok, map}
        other -> {:error, "unexpected yaml response: #{inspect(other)}"}
      end
    rescue
      error -> {:error, Exception.message(error)}
    end
  end

  defp duration_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end
end
