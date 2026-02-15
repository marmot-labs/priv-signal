defmodule PrivSignal.Scan.Classifier do
  @moduledoc false

  alias PrivSignal.Scan.Finding

  @confirmed_evidence_types [:direct_field_access, :key_match, :pii_container]

  def classify(candidates) when is_list(candidates) do
    candidates
    |> Enum.map(&classify_one/1)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&{&1.file, &1.line, &1.module, &1.function, &1.arity, &1.sink, &1.id})
  end

  def classify_one(candidate) when is_map(candidate) do
    evidence_types = Enum.map(candidate.evidence || [], & &1.type)
    classification = classification(evidence_types)
    confidence = confidence(classification)
    matched_fields = candidate.matched_fields || []

    %Finding{
      id: fingerprint(candidate, evidence_types, matched_fields),
      classification: classification,
      confidence: confidence,
      confidence_hint: Map.get(candidate, :confidence_hint),
      sensitivity: sensitivity(matched_fields),
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
      matched_fields: matched_fields,
      evidence: candidate.evidence || []
    }
  end

  def stable_sort(findings) when is_list(findings) do
    Enum.sort_by(findings, &{&1.file, &1.line, &1.module, &1.function, &1.arity, &1.sink, &1.id})
  end

  defp classification(evidence_types) do
    if Enum.any?(evidence_types, &(&1 in @confirmed_evidence_types)) do
      :confirmed_pii
    else
      :possible_pii
    end
  end

  defp confidence(:confirmed_pii), do: :confirmed
  defp confidence(:possible_pii), do: :possible

  defp sensitivity([]), do: :unknown

  defp sensitivity(fields) do
    fields
    |> Enum.map(&Map.get(&1, :sensitivity, "medium"))
    |> Enum.map(&normalize_sensitivity/1)
    |> Enum.max_by(&sensitivity_rank/1, fn -> "unknown" end)
    |> String.to_atom()
  end

  defp normalize_sensitivity(value) when value in ["low", "medium", "high"], do: value
  defp normalize_sensitivity(_), do: "unknown"

  defp sensitivity_rank("unknown"), do: 0
  defp sensitivity_rank("low"), do: 1
  defp sensitivity_rank("medium"), do: 2
  defp sensitivity_rank("high"), do: 3

  defp fingerprint(candidate, evidence_types, matched_fields) do
    sorted_types =
      evidence_types
      |> Enum.map(&Atom.to_string/1)
      |> Enum.sort()

    sorted_fields =
      matched_fields
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
    name = Map.get(field, :name) || ""
    category = Map.get(field, :category) || ""
    sensitivity = Map.get(field, :sensitivity) || ""
    Enum.join([module, name, category, sensitivity], "|")
  end
end
