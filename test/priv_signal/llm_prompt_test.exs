defmodule PrivSignal.LLM.PromptTest do
  use ExUnit.Case, async: true

  alias PrivSignal.LLM.Prompt

  test "builds messages with diff and config summary" do
    diff = "diff --git a/a b/a\n+new line"

    summary = %{
      version: 1,
      pii: [
        %{
          module: "MyApp.User",
          fields: [%{name: "email", category: "contact", sensitivity: "medium"}]
        }
      ],
      pii_modules: ["MyApp.User"],
      flows: []
    }

    messages = Prompt.build(diff, summary)

    assert [%{role: "system"}, %{role: "user", content: content}] = messages
    assert String.contains?(content, "priv-signal.yml config summary")
    assert String.contains?(content, "git diff (unified)")
    assert String.contains?(content, diff)
  end
end
