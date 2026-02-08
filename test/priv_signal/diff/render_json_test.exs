defmodule PrivSignal.Diff.Render.JSONTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Diff.Render.JSON

  test "renders stable json contract with summary counts" do
    report = %{
      metadata: %{
        base_ref: "origin/main",
        candidate_source: %{type: :workspace, path: "priv-signal-infer.json"},
        schema_version_base: "1.2",
        schema_version_candidate: "1.2"
      },
      changes: [
        %{
          type: "flow_removed",
          flow_id: "z_flow",
          change: "flow_removed",
          severity: "low",
          rule_id: "R-LOW-FLOW-REMOVED",
          details: %{}
        },
        %{
          type: "flow_changed",
          flow_id: "a_flow",
          change: "external_sink_added",
          severity: "high",
          rule_id: "R-HIGH-EXTERNAL-SINK-ADDED",
          details: %{after_sink: %{kind: "mailgun", subtype: "send"}}
        },
        %{
          type: "flow_added",
          flow_id: "m_flow",
          change: "flow_added",
          severity: "medium",
          rule_id: "R-MEDIUM-INTERNAL-FLOW-ADDED",
          details: %{boundary: "internal"}
        }
      ]
    }

    rendered = JSON.render(report)

    assert rendered.version == "v1"
    assert rendered.metadata.base_ref == "origin/main"
    assert rendered.summary.high == 1
    assert rendered.summary.medium == 1
    assert rendered.summary.low == 1
    assert rendered.summary.total == 3

    [first | _] = rendered.changes
    assert first.severity == "high"
    assert first.flow_id == "a_flow"
  end

  test "schema version is explicit and stable" do
    assert JSON.schema_version() == "v1"
  end
end
