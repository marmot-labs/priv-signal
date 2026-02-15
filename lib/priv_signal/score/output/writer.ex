defmodule PrivSignal.Score.Output.Writer do
  @moduledoc false

  def write(json, opts \\ []) when is_map(json) do
    output_path = Keyword.get(opts, :output, "priv_signal_score.json")

    with :ok <- ensure_parent_dir(output_path),
         :ok <- File.write(output_path, Jason.encode!(json, pretty: true)) do
      {:ok, output_path}
    end
  end

  defp ensure_parent_dir(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end
end
