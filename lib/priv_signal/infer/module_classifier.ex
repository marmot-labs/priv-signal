defmodule PrivSignal.Infer.ModuleClassifier do
  @moduledoc false

  alias PrivSignal.Infer.ModuleClassification

  def classify(module_name, file_path, opts \\ []) do
    module_name = normalize_module(module_name)
    file_path = normalize_path(file_path)

    module_signals = module_signals(module_name)
    path_signals = path_signals(file_path)

    all_signals = module_signals ++ path_signals
    min_confidence = Keyword.get(opts, :min_confidence, 0.7)

    case best_match(all_signals) do
      nil ->
        nil

      {kind, confidence, evidence_signals} when confidence >= min_confidence ->
        %ModuleClassification{
          kind: kind,
          confidence: confidence,
          evidence_signals: evidence_signals
        }

      _ ->
        nil
    end
  end

  defp module_signals(nil), do: []

  defp module_signals(module_name) do
    [
      suffix_signal(module_name, "controller", "Controller", 0.98),
      suffix_signal(module_name, "liveview", "LiveView", 0.98),
      suffix_signal(module_name, "liveview", "Live", 0.92),
      suffix_signal(module_name, "job", "Job", 0.95),
      suffix_signal(module_name, "worker", "Worker", 0.95)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp path_signals(nil), do: []

  defp path_signals(file_path) do
    [
      contains_signal(file_path, "/controllers/", "controller", 0.88),
      contains_signal(file_path, "/live/", "liveview", 0.85),
      contains_signal(file_path, "/jobs/", "job", 0.85),
      contains_signal(file_path, "/workers/", "worker", 0.85)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp best_match(signals) when is_list(signals) do
    signals
    |> Enum.group_by(fn {kind, _confidence, _signal} -> kind end)
    |> Enum.map(fn {kind, entries} ->
      confidence = entries |> Enum.map(fn {_k, score, _s} -> score end) |> Enum.max(fn -> 0.0 end)
      evidence_signals = entries |> Enum.map(fn {_k, _score, signal} -> signal end) |> Enum.uniq()
      {kind, confidence, evidence_signals}
    end)
    |> Enum.max_by(fn {_kind, confidence, _signals} -> confidence end, fn -> nil end)
  end

  defp suffix_signal(module_name, kind, suffix, confidence) do
    if String.ends_with?(module_name, suffix) do
      {kind, confidence, "module_suffix:" <> suffix}
    else
      nil
    end
  end

  defp contains_signal(file_path, pattern, kind, confidence) do
    if String.contains?(file_path, pattern) do
      {kind, confidence, "path_contains:" <> pattern}
    else
      nil
    end
  end

  defp normalize_module(nil), do: nil

  defp normalize_module(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> normalize_module()
  end

  defp normalize_module(module) when is_binary(module) do
    module
    |> String.trim()
    |> case do
      "" -> nil
      "Elixir." <> rest -> rest
      value -> value
    end
  end

  defp normalize_module(_), do: nil

  defp normalize_path(nil), do: nil

  defp normalize_path(path) when is_binary(path) do
    path
    |> String.replace("\\", "/")
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_path(_), do: nil
end
