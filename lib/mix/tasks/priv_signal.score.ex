defmodule Mix.Tasks.PrivSignal.Score do
  use Mix.Task

  @shortdoc "Score a PR for privacy risk (Phase 0: config only)"

  @moduledoc """
  Validates priv-signal.yml. Later phases will run full analysis.
  """

  @impl true
  def run(args) do
    _ = PrivSignal.Runtime.ensure_started()
    options = PrivSignal.Git.Options.parse(args)

    with {:ok, config} <- load_config(),
         {:ok, diff} <- load_diff(options) do
      summary = PrivSignal.Config.Summary.build(config)
      messages = PrivSignal.LLM.Prompt.build(diff, summary)

      result =
        with {:ok, raw} <- PrivSignal.LLM.Client.request(messages),
             {:ok, validated} <- PrivSignal.Analysis.Validator.validate(raw, diff) do
          normalized = PrivSignal.Analysis.Normalizer.normalize(validated)
          events = PrivSignal.Analysis.Events.from_payload(normalized)
          PrivSignal.Risk.Assessor.assess(events, flows: config.flows)
        else
          {:error, errors} when is_list(errors) -> fallback(errors)
          {:error, error} -> fallback([error])
        end

      markdown = PrivSignal.Output.Markdown.render(result)
      json = PrivSignal.Output.JSON.render(result)

      case PrivSignal.Output.Writer.write(markdown, json) do
        {:ok, path} -> Mix.shell().info("Wrote JSON output to #{path}")
        {:error, reason} -> Mix.shell().error("Failed to write JSON output: #{inspect(reason)}")
      end
    else
      {:error, errors} when is_list(errors) -> render_errors(errors)
      {:error, error} -> render_errors(error)
    end
  end

  defp render_errors(errors) when is_list(errors) do
    Enum.each(errors, fn error ->
      Mix.shell().error("- #{format_error(error)}")
    end)
  end

  defp render_errors(error) do
    Mix.shell().error("- #{format_error(error)}")
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)

  defp load_config do
    case PrivSignal.Config.Loader.load() do
      {:ok, config} ->
        Mix.shell().info("priv-signal.yml is valid")
        {:ok, config}

      {:error, errors} ->
        Mix.shell().error("priv-signal.yml is invalid")
        render_errors(errors)
        {:error, errors}
    end
  end

  defp load_diff(options) do
    case PrivSignal.Git.Diff.get(options.base, options.head) do
      {:ok, diff} ->
        Mix.shell().info("git diff loaded (#{byte_size(diff)} bytes)")
        {:ok, diff}

      {:error, error} ->
        Mix.shell().error("git diff failed: #{error}")
        {:error, error}
    end
  end

  defp fallback(errors) do
    Mix.shell().error("LLM analysis failed; falling back to NONE")
    render_errors(errors)

    %{category: :none, reasons: [], events: []}
  end
end
