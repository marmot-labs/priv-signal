defmodule PrivSignal.Git.Diff do
  @moduledoc false

  def get(base, head, opts \\ []) do
    start = System.monotonic_time()
    runner = Keyword.get(opts, :runner, &System.cmd/3)

    {output, status} =
      runner.("git", ["diff", "--unified=3", "#{base}..#{head}"], stderr_to_stdout: true)

    result =
      if status == 0 do
        {:ok, output}
      else
        {:error, "git diff failed (status #{status}): #{String.trim(output)}"}
      end

    PrivSignal.Telemetry.emit(
      [:priv_signal, :git, :diff],
      %{duration_ms: duration_ms(start)},
      %{base: base, head: head, ok: status == 0}
    )

    result
  end

  defp duration_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end
end
