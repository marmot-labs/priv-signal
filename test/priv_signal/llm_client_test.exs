defmodule PrivSignal.LLM.ClientTest do
  use ExUnit.Case, async: true

  alias PrivSignal.LLM.Client

  test "uses env vars for config defaults" do
    System.put_env("PRIV_SIGNAL_MODEL_API_KEY", "test-key")
    System.put_env("PRIV_SIGNAL_MODEL_URL", "https://example.com")
    System.put_env("PRIV_SIGNAL_MODEL", "gpt-test")
    System.put_env("PRIV_SIGNAL_SECONDARY_API_KEY", "org-key")

    config = Client.config()

    assert config.api_key == "test-key"
    assert config.base_url == "https://example.com"
    assert config.model == "gpt-test"
    assert config.secondary_key == "org-key"
  after
    System.delete_env("PRIV_SIGNAL_MODEL_API_KEY")
    System.delete_env("PRIV_SIGNAL_MODEL_URL")
    System.delete_env("PRIV_SIGNAL_MODEL")
    System.delete_env("PRIV_SIGNAL_SECONDARY_API_KEY")
  end

  test "parses JSON content from a mocked response" do
    request = fn _opts ->
      {:ok,
       %{
         status: 200,
         body: %{
           "choices" => [
             %{
               "message" => %{
                 "content" =>
                   "{\"touched_flows\":[],\"new_pii\":[],\"new_sinks\":[],\"notes\":[]}"
               }
             }
           ]
         }
       }}
    end

    messages = [%{role: "user", content: "hello"}]

    assert {:ok, json} =
             Client.request(messages,
               api_key: "key",
               base_url: "https://example.com",
               model: "gpt-5",
               request: request
             )

    assert json["notes"] == []
  end
end
