defmodule PrivSignal.Output.MarkdownTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Output.Markdown

  test "renders summary with reasons and events" do
    result = %{
      category: :medium,
      reasons: ["Introduces new PII categories"],
      events: [
        %{
          type: :new_pii,
          pii_category: "email",
          summary: "Added email field",
          evidence: "lib/foo.ex:10",
          confidence: 0.9
        }
      ]
    }

    output = Markdown.render(result)

    assert String.contains?(output, "Category:")
    assert String.contains?(output, "MEDIUM")
    assert String.contains?(output, "Introduces new PII categories")
    assert String.contains?(output, "lib/foo.ex:10")
  end
end
