defmodule PrivSignal.Score.Advisory do
  @moduledoc false

  require Logger

  def run(diff, report, llm_config, opts \\ [])
      when is_map(diff) and is_map(report) and is_map(llm_config) do
    if Map.get(llm_config, :enabled, false) do
      do_run(diff, report, llm_config, opts)
    else
      {:ok, nil}
    end
  end

  defp do_run(diff, report, llm_config, opts) do
    start = System.monotonic_time()
    PrivSignal.Telemetry.emit([:priv_signal, :score, :advisory, :start], %{}, %{ok: true})

    messages =
      build_messages(diff, report)

    request_opts =
      opts
      |> Keyword.take([:request])
      |> Keyword.put(:model, Map.get(llm_config, :model))
      |> Keyword.put(:receive_timeout_ms, Map.get(llm_config, :timeout_ms))

    result = PrivSignal.LLM.Client.request(messages, request_opts)

    duration_ms = duration_ms(start)

    case result do
      {:ok, payload} ->
        PrivSignal.Telemetry.emit(
          [:priv_signal, :score, :advisory, :stop],
          %{duration_ms: duration_ms},
          %{ok: true}
        )

        {:ok, normalize_payload(payload)}

      {:error, reason} ->
        Logger.warning("[priv_signal] advisory interpretation failed reason=#{inspect(reason)}")

        PrivSignal.Telemetry.emit(
          [:priv_signal, :score, :advisory, :error],
          %{duration_ms: duration_ms},
          %{ok: false, reason: inspect(reason)}
        )

        {:error, reason}
    end
  end

  defp normalize_payload(payload) when is_map(payload) do
    %{
      summary: get(payload, :summary),
      risk_assessment: get(payload, :risk_assessment),
      suggested_review_focus: get(payload, :suggested_review_focus)
    }
  end

  defp normalize_payload(_),
    do: %{summary: nil, risk_assessment: nil, suggested_review_focus: nil}

  defp build_messages(diff, report) do
    [
      %{
        role: "system",
        content:
          "You are a privacy reviewer. Return JSON with keys summary, risk_assessment, suggested_review_focus."
      },
      %{
        role: "user",
        content:
          Jason.encode!(%{
            diff_summary: Map.get(diff, :summary, %{}),
            score: Map.get(report, :score),
            reasons: Map.get(report, :reasons, [])
          })
      }
    ]
  end

  defp duration_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end

  defp get(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
