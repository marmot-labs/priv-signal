defmodule PrivSignal.LLM.PromptTest do
  use ExUnit.Case, async: true

  alias PrivSignal.LLM.Prompt

  test "builds messages with diff and config summary" do
    diff = "diff --git a/a b/a\n+new line"
    summary = %{version: 1, pii_modules: ["MyApp.User"], flows: []}

    messages = Prompt.build(diff, summary)

    assert [%{role: "system"}, %{role: "user", content: content}] = messages
    assert String.contains?(content, "CONFIG SUMMARY")
    assert String.contains?(content, "DIFF (unified)")
    assert String.contains?(content, diff)
  end
end
