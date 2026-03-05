defmodule PrivSignal.Diff.SemanticV2Test do
  use ExUnit.Case, async: true

  alias PrivSignal.Diff.{Semantic, SemanticV2, Severity}
  alias PrivSignal.Test.DiffFixtureHelper

  test "builds deterministic v2 events from annotated semantic changes" do
    base = DiffFixtureHelper.load_fixture!("sink_changed", :base)
    candidate = DiffFixtureHelper.load_fixture!("sink_changed", :candidate)

    events =
      base
      |> Semantic.compare(candidate)
      |> Severity.annotate()
      |> SemanticV2.from_changes()

    assert is_list(events)
    assert length(events) > 0

    assert Enum.all?(events, fn event ->
             is_binary(event.event_id) and is_binary(event.event_type) and
               is_binary(event.event_class)
           end)

    assert Enum.any?(events, &(&1.event_type in ["destination_changed", "boundary_changed"]))
  end

  test "produces stable ordering independent of input ordering" do
    base = DiffFixtureHelper.load_fixture!("fields_changed", :base)
    candidate = DiffFixtureHelper.load_fixture!("fields_changed", :candidate)

    changes =
      base
      |> Semantic.compare(candidate)
      |> Severity.annotate()

    assert SemanticV2.from_changes(changes) == SemanticV2.from_changes(Enum.reverse(changes))
  end

  test "emits transform_delta.removed for sensitive context linkage removal" do
    changes = [
      %{
        type: "flow_changed",
        flow_id: "psfs_flow_1",
        change: "sensitive_context_linkage_removed",
        severity: "low",
        rule_id: "R-LOW-DEFAULT",
        details: %{
          source: "Demo.User.user_id",
          source_class: "persistent_pseudonymous_identifier",
          boundary: "external",
          removed_links: ["Demo.User.accommodation_status"]
        }
      }
    ]

    [event] = SemanticV2.from_changes(changes)

    assert event.event_type == "transform_changed"
    assert event.boundary_after == "external"
    assert event.transform_delta["removed"] == ["Demo.User.accommodation_status"]
  end
end
