defmodule PrivSignal.LLM.SchemaTest do
  use ExUnit.Case, async: true

  alias PrivSignal.LLM.Schema

  test "accepts required keys" do
    payload = %{
      "touched_flows" => [],
      "new_pii" => [],
      "new_sinks" => [],
      "notes" => []
    }

    assert {:ok, _} = Schema.validate(payload)
  end

  test "rejects missing keys" do
    assert {:error, errors} = Schema.validate(%{})
    assert "missing key: touched_flows" in errors
  end
end
