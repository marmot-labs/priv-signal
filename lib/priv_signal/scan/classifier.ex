defmodule PrivSignal.Scan.Classifier do
  @moduledoc """
  Converts raw scanner candidates into sorted, severity-labeled findings.
  """

  alias PrivSignal.Scan.Finding

  @confirmed_evidence_types [:direct_field_access, :key_match, :prd_container]
  @probable_evidence_types [:indirect_payload_ref, :inherited_db_wrapper]

  def classify(candidates) when is_list(candidates) do
    candidates
    |> Enum.map(&classify_one/1)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&{&1.file, &1.line, &1.module, &1.function, &1.arity, &1.sink, &1.id})
  end

  def classify_one(candidate) when is_map(candidate) do
    evidence_types = Enum.map(candidate.evidence || [], & &1.type)
    match_sources = Enum.map(candidate.evidence || [], &Map.get(&1, :match_source))
    classification = classification(evidence_types)
    confidence = confidence(classification, evidence_types, match_sources)
    matched_nodes = candidate.matched_nodes || []

    %Finding{
      id: fingerprint(candidate, evidence_types, matched_nodes),
      classification: classification,
      confidence: confidence,
      confidence_hint: Map.get(candidate, :confidence_hint),
      sensitivity: sensitivity(matched_nodes),
      data_classes: data_classes(matched_nodes),
      module: candidate.module,
      function: candidate.function,
      arity: candidate.arity,
      file: candidate.file,
      line: candidate.line,
      node_type_hint: Map.get(candidate, :node_type_hint),
      role_kind: Map.get(candidate, :role_kind),
      role_subtype: Map.get(candidate, :role_subtype),
      boundary: Map.get(candidate, :boundary),
      sink: candidate.sink,
      matched_nodes: matched_nodes,
      evidence: candidate.evidence || []
    }
  end

  def stable_sort(findings) when is_list(findings) do
    Enum.sort_by(findings, &{&1.file, &1.line, &1.module, &1.function, &1.arity, &1.sink, &1.id})
  end

  defp classification(evidence_types) do
    if Enum.any?(evidence_types, &(&1 in @confirmed_evidence_types)) do
      :confirmed_prd
    else
      :possible_prd
    end
  end

  defp confidence(:confirmed_prd, evidence_types, match_sources) do
    cond do
      has_exact_match?(match_sources) and
          Enum.any?(evidence_types, &(&1 in @confirmed_evidence_types)) ->
        :confirmed

      Enum.any?(evidence_types, &(&1 in @probable_evidence_types)) or
          Enum.any?(match_sources, &(&1 in [:normalized, :alias])) ->
        :probable

      true ->
        :possible
    end
  end

  defp confidence(:possible_prd, evidence_types, match_sources) do
    if Enum.any?(evidence_types, &(&1 in @probable_evidence_types)) or
         Enum.any?(match_sources, &(&1 in [:normalized, :alias])) do
      :probable
    else
      :possible
    end
  end

  defp sensitivity([]), do: :unknown

  defp sensitivity(nodes) do
    nodes
    |> Enum.map(&node_sensitivity/1)
    |> Enum.max_by(&sensitivity_rank/1, fn -> "unknown" end)
    |> String.to_atom()
  end

  defp data_classes(nodes) do
    nodes
    |> Enum.map(&Map.get(&1, :class))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp node_sensitivity(node) do
    cond do
      Map.get(node, :sensitive) == true ->
        "high"

      Map.get(node, :sensitive) == false ->
        "medium"

      true ->
        "unknown"
    end
  end

  defp sensitivity_rank("unknown"), do: 0
  defp sensitivity_rank("low"), do: 1
  defp sensitivity_rank("medium"), do: 2
  defp sensitivity_rank("high"), do: 3

  defp has_exact_match?(match_sources) do
    Enum.any?(match_sources, &(&1 == :exact or is_nil(&1)))
  end

  defp fingerprint(candidate, evidence_types, matched_nodes) do
    sorted_types =
      evidence_types
      |> Enum.map(&Atom.to_string/1)
      |> Enum.sort()

    sorted_fields =
      matched_nodes
      |> Enum.map(&field_key/1)
      |> Enum.sort()

    payload =
      [
        candidate.file,
        candidate.line,
        Map.get(candidate, :node_type_hint),
        Map.get(candidate, :role_kind),
        Map.get(candidate, :role_subtype),
        candidate.sink,
        Enum.join(sorted_fields, ","),
        Enum.join(sorted_types, ",")
      ]
      |> Enum.map(&to_string/1)
      |> Enum.join(":")

    payload
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  defp field_key(field) do
    module = Map.get(field, :module) || ""
    key = Map.get(field, :key) || ""
    name = Map.get(field, :field) || Map.get(field, :name) || ""
    class = Map.get(field, :class) || ""
    sensitive = Map.get(field, :sensitive)
    Enum.join([module, key, name, class, inspect(sensitive)], "|")
  end
end
