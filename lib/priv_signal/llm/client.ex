defmodule PrivSignal.LLM.Client do
  @moduledoc false
  require Logger

  @default_base_url "https://api.openai.com"
  @default_model "gpt-5"
  @default_connect_timeout_ms 30_000
  @default_receive_timeout_ms 60_000
  @default_pool_timeout_ms 5_000

  def request(messages, opts \\ []) when is_list(messages) do
    config = config(opts)
    start = System.monotonic_time()

    result =
      with :ok <- ensure_api_key(config),
           {:ok, response} <- do_request(messages, config, opts),
           {:ok, body} <- normalize_body(response, config),
           {:ok, content} <- extract_content(body),
           {:ok, json} <- decode_json(content) do
        {:ok, json}
      end

    PrivSignal.Telemetry.emit(
      [:priv_signal, :llm, :request],
      %{duration_ms: duration_ms(start)},
      %{ok: match?({:ok, _}, result), model: config.model, base_url: config.base_url}
    )

    result
  end

  def config(opts \\ []) do
    %{
      api_key: Keyword.get(opts, :api_key) || System.get_env("PRIV_SIGNAL_MODEL_API_KEY"),
      secondary_key: Keyword.get(opts, :secondary_key) || System.get_env("PRIV_SIGNAL_SECONDARY_API_KEY"),
      base_url: Keyword.get(opts, :base_url) || System.get_env("PRIV_SIGNAL_MODEL_URL") || @default_base_url,
      model: Keyword.get(opts, :model) || System.get_env("PRIV_SIGNAL_MODEL") || @default_model,
      debug: Keyword.get(opts, :debug) || env_truthy?("PRIV_SIGNAL_DEBUG"),
      connect_timeout_ms:
        parse_timeout(
          Keyword.get(opts, :connect_timeout_ms) || System.get_env("PRIV_SIGNAL_TIMEOUT_MS"),
          @default_connect_timeout_ms
        ),
      receive_timeout_ms:
        parse_timeout(
          Keyword.get(opts, :receive_timeout_ms) || System.get_env("PRIV_SIGNAL_RECV_TIMEOUT_MS"),
          @default_receive_timeout_ms
        ),
      pool_timeout_ms:
        parse_timeout(
          Keyword.get(opts, :pool_timeout_ms) || System.get_env("PRIV_SIGNAL_POOL_TIMEOUT_MS"),
          @default_pool_timeout_ms
        )
    }
  end

  defp ensure_api_key(%{api_key: nil}), do: {:error, "PRIV_SIGNAL_MODEL_API_KEY is required"}
  defp ensure_api_key(_), do: :ok

  defp do_request(messages, config, opts) do
    request_fn = Keyword.get(opts, :request, &Req.request/1)

    headers =
      [
        {"authorization", "Bearer #{config.api_key}"},
        {"content-type", "application/json"}
      ]
      |> maybe_add_org_header(config.secondary_key)

    request = [
      method: :post,
      url: String.trim_trailing(config.base_url, "/") <> "/v1/chat/completions",
      headers: headers,
      connect_options: [timeout: config.connect_timeout_ms],
      receive_timeout: config.receive_timeout_ms,
      pool_timeout: config.pool_timeout_ms,
      json: %{
        model: config.model,
        messages: messages
      }
    ]

    debug_request(config, request, messages)
    result = request_fn.(request)
    debug_result(config, result)
    result
  end

  defp maybe_add_org_header(headers, nil), do: headers
  defp maybe_add_org_header(headers, secondary_key), do: headers ++ [{"openai-organization", secondary_key}]

  defp normalize_body(%{status: status} = response, _config) when status in 200..299 do
    body = Map.get(response, :body)
    {:ok, body}
  end

  defp normalize_body(%{status: status, body: body}, config) do
    debug_error_body(config, status, body)
    {:error, "LLM request failed (status #{status}): #{inspect(body)}"}
  end

  defp normalize_body(other, config) do
    debug_unexpected_response(config, other)
    {:error, "unexpected LLM response: #{inspect(other)}"}
  end

  defp extract_content(%{"choices" => [%{"message" => %{"content" => content}} | _]}) when is_binary(content) do
    {:ok, content}
  end

  defp extract_content(%{choices: [%{message: %{content: content}} | _]}) when is_binary(content) do
    {:ok, content}
  end

  defp extract_content(other), do: {:error, "unexpected LLM response shape: #{inspect(other)}"}

  defp decode_json(content) do
    case Jason.decode(content) do
      {:ok, json} -> {:ok, json}
      {:error, error} -> {:error, "invalid JSON in LLM content: #{Exception.message(error)}"}
    end
  end

  defp duration_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end

  defp parse_timeout(nil, default), do: default
  defp parse_timeout(:infinity, _default), do: :infinity
  defp parse_timeout("infinity", _default), do: :infinity
  defp parse_timeout(value, _default) when is_integer(value) and value >= 0, do: value

  defp parse_timeout(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int >= 0 -> int
      _ -> default
    end
  end

  defp parse_timeout(_value, default), do: default

  defp env_truthy?(key) do
    case System.get_env(key) do
      nil -> false
      value when is_binary(value) ->
        String.downcase(String.trim(value)) in ["1", "true", "yes", "y", "on"]
      _ ->
        false
    end
  end

  defp debug_request(%{debug: false}, _request, _messages), do: :ok

  defp debug_request(config, request, messages) do
    safe_headers = redact_headers(Keyword.get(request, :headers, []))
    message_stats = summarize_messages(messages)

    Logger.info("""
    [priv_signal] LLM request debug
      url: #{Keyword.get(request, :url)}
      model: #{config.model}
      api_key_present: #{not is_nil(config.api_key)}
      headers: #{inspect(safe_headers)}
      connect_timeout_ms: #{config.connect_timeout_ms}
      receive_timeout_ms: #{config.receive_timeout_ms}
      pool_timeout_ms: #{config.pool_timeout_ms}
      message_stats: #{inspect(message_stats)}
    """)
  end

  defp debug_result(%{debug: false}, _result), do: :ok

  defp debug_result(_config, {:ok, %{status: status, headers: headers}}) do
    Logger.info("[priv_signal] LLM response status=#{status} headers=#{inspect(headers)}")
  end

  defp debug_result(_config, {:ok, %{status: status} = response}) do
    Logger.info("[priv_signal] LLM response status=#{status} keys=#{inspect(Map.keys(response))}")
  end

  defp debug_result(_config, {:error, error}) do
    Logger.info("[priv_signal] LLM transport error=#{inspect(error)}")
  end

  defp debug_error_body(%{debug: false}, _status, _body), do: :ok

  defp debug_error_body(_config, status, body) do
    Logger.info("[priv_signal] LLM non-2xx response status=#{status} body=#{inspect(body, limit: 200, printable_limit: 200)}")
  end

  defp debug_unexpected_response(%{debug: false}, _other), do: :ok

  defp debug_unexpected_response(_config, other) do
    Logger.info("[priv_signal] LLM unexpected response=#{inspect(other, limit: 200, printable_limit: 200)}")
  end

  defp redact_headers(headers) do
    Enum.map(headers, fn
      {key, value} when is_binary(key) ->
        if sensitive_header?(key) do
          {key, "<<redacted>>"}
        else
          {key, value}
        end

      other ->
        other
    end)
  end

  defp sensitive_header?(key) do
    key
    |> String.downcase()
    |> then(fn lower ->
      lower in ["authorization", "openai-organization", "x-api-key", "api-key"] or
        String.contains?(lower, "authorization") or
        String.contains?(lower, "api-key")
    end)
  end

  defp summarize_messages(messages) when is_list(messages) do
    roles =
      messages
      |> Enum.map(fn
        %{"role" => role} -> role
        %{role: role} -> role
        _ -> "unknown"
      end)

    content_sizes =
      messages
      |> Enum.map(fn
        %{"content" => content} when is_binary(content) -> byte_size(content)
        %{content: content} when is_binary(content) -> byte_size(content)
        _ -> 0
      end)

    %{
      count: length(messages),
      roles: roles,
      content_bytes: content_sizes,
      total_content_bytes: Enum.sum(content_sizes)
    }
  end
end
