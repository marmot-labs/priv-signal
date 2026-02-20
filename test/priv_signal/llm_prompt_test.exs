defmodule PrivSignal.LLM.PromptTest do
  use ExUnit.Case, async: true

  alias PrivSignal.LLM.Prompt

  test "builds messages with diff and config summary" do
    diff = "diff --git a/a b/a\n+new line"

    summary = %{
      version: 1,
      prd_nodes: [
        %{
          key: "user_email",
          label: "User Email",
          class: "direct_identifier",
          sensitive: true,
          scope: %{module: "MyApp.User", field: "email"}
        }
      ],
      prd_modules: ["MyApp.User"]
    }

    messages = Prompt.build(diff, summary)

    assert [%{role: "system"}, %{role: "user", content: content}] = messages
    assert String.contains?(content, "priv_signal.yml config summary")
    assert String.contains?(content, "git diff (unified)")
    assert String.contains?(content, diff)
  end
end
