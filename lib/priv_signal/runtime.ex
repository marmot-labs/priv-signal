defmodule PrivSignal.Runtime do
  @moduledoc false

  def ensure_started do
    _ = Application.ensure_all_started(:telemetry)
    _ = Application.ensure_all_started(:finch)
    _ = Application.ensure_all_started(:req)

    ensure_finch()
  end

  defp ensure_finch do
    case Process.whereis(Req.Finch) do
      nil ->
        case Finch.start_link(name: Req.Finch) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _pid ->
        :ok
    end
  end
end
