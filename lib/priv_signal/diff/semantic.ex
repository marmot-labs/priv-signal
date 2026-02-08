defmodule PrivSignal.Diff.Semantic do
  @moduledoc false

  alias PrivSignal.Diff.Normalize

  def compare(base_artifact, candidate_artifact, opts \\ []) do
    include_confidence? = Keyword.get(opts, :include_confidence, false)

    base = Normalize.normalize(base_artifact)
    candidate = Normalize.normalize(candidate_artifact)

    compare_normalized(base, candidate, include_confidence: include_confidence?)
  end

  def compare_normalized(base, candidate, opts \\ []) when is_map(base) and is_map(candidate) do
    include_confidence? = Keyword.get(opts, :include_confidence, false)

    added_ids = MapSet.difference(candidate.flow_ids, base.flow_ids) |> MapSet.to_list()
    removed_ids = MapSet.difference(base.flow_ids, candidate.flow_ids) |> MapSet.to_list()
    shared_ids = MapSet.intersection(base.flow_ids, candidate.flow_ids) |> MapSet.to_list()

    added =
      added_ids
      |> Enum.map(fn flow_id ->
        flow = Map.fetch!(candidate.flows_by_id, flow_id)

        change(:flow_added, flow_id, "flow_added", %{
          source: flow.source,
          sink: flow.sink,
          boundary: flow.boundary
        })
      end)

    removed =
      removed_ids
      |> Enum.map(fn flow_id ->
        flow = Map.fetch!(base.flows_by_id, flow_id)

        change(:flow_removed, flow_id, "flow_removed", %{
          source: flow.source,
          sink: flow.sink,
          boundary: flow.boundary
        })
      end)

    changed =
      shared_ids
      |> Enum.flat_map(fn flow_id ->
        base_flow = Map.fetch!(base.flows_by_id, flow_id)
        candidate_flow = Map.fetch!(candidate.flows_by_id, flow_id)
        flow_changes(base_flow, candidate_flow, include_confidence?)
      end)

    (added ++ removed ++ changed)
    |> stable_sort_changes()
  end

  def stable_sort_changes(changes) when is_list(changes) do
    Enum.sort_by(changes, fn change ->
      {change.type, change.flow_id, change.change, stable_details_key(change.details)}
    end)
  end

  defp flow_changes(base_flow, candidate_flow, include_confidence?) do
    sink_change = sink_change(base_flow, candidate_flow)
    boundary_change = boundary_change(base_flow, candidate_flow)
    pii_change = pii_change(base_flow, candidate_flow)
    confidence_change = confidence_change(base_flow, candidate_flow, include_confidence?)

    Enum.reject([sink_change, boundary_change, pii_change, confidence_change], &is_nil/1)
  end

  defp sink_change(base_flow, candidate_flow) do
    if base_flow.sink != candidate_flow.sink do
      change_type =
        if base_flow.boundary == "internal" and candidate_flow.boundary == "external" do
          "external_sink_added"
        else
          "external_sink_added_removed"
        end

      change(:flow_changed, base_flow.id, change_type, %{
        before_sink: base_flow.sink,
        after_sink: candidate_flow.sink
      })
    end
  end

  defp boundary_change(base_flow, candidate_flow) do
    if base_flow.boundary != candidate_flow.boundary do
      change(:flow_changed, base_flow.id, "boundary_changed", %{
        before_boundary: base_flow.boundary,
        after_boundary: candidate_flow.boundary
      })
    end
  end

  defp pii_change(base_flow, candidate_flow) do
    added = MapSet.difference(candidate_flow.source_fields, base_flow.source_fields)
    removed = MapSet.difference(base_flow.source_fields, candidate_flow.source_fields)

    cond do
      MapSet.size(added) > 0 ->
        change(:flow_changed, base_flow.id, "pii_fields_expanded", %{
          added_fields: added |> MapSet.to_list() |> Enum.sort(),
          before_source: base_flow.source,
          after_source: candidate_flow.source
        })

      MapSet.size(removed) > 0 ->
        change(:flow_changed, base_flow.id, "pii_fields_reduced", %{
          removed_fields: removed |> MapSet.to_list() |> Enum.sort(),
          before_source: base_flow.source,
          after_source: candidate_flow.source
        })

      true ->
        nil
    end
  end

  defp confidence_change(_base_flow, _candidate_flow, false), do: nil

  defp confidence_change(base_flow, candidate_flow, true) do
    if base_flow.confidence != candidate_flow.confidence do
      change(:confidence_changed, base_flow.id, "confidence_changed", %{
        before_confidence: base_flow.confidence,
        after_confidence: candidate_flow.confidence
      })
    end
  end

  defp change(type, flow_id, change, details) do
    %{
      type: Atom.to_string(type),
      flow_id: flow_id,
      change: change,
      details: details
    }
  end

  defp stable_details_key(details) when is_map(details) do
    details
    |> Enum.map(fn {key, value} -> {key, stable_value_key(value)} end)
    |> Enum.sort()
  end

  defp stable_value_key(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> {key, stable_value_key(nested)} end)
    |> Enum.sort()
  end

  defp stable_value_key(value) when is_list(value), do: Enum.map(value, &stable_value_key/1)
  defp stable_value_key(value), do: value
end
