defmodule Mix.Tasks.PrivSignal.ScoreTest do
  use ExUnit.Case

  test "validates priv-signal.yml and reports success" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "priv_signal_score_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    File.cd!(tmp_dir, fn ->
      File.write!("priv-signal.yml", sample_yaml())

      Mix.shell(Mix.Shell.Process)
      Mix.Tasks.PrivSignal.Score.run([])

      assert_received {:mix_shell, :info, ["priv-signal.yml is valid"]}
      assert_received {:mix_shell, :error, [message]}
      assert String.starts_with?(message, "git diff failed:")
    end)
  end

  test "fails fast when validation fails" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "priv_signal_score_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    File.cd!(tmp_dir, fn ->
      File.write!("priv-signal.yml", failing_yaml())

      Mix.shell(Mix.Shell.Process)

      assert_raise Mix.Error, ~r/data flow validation failed/, fn ->
        Mix.Tasks.PrivSignal.Score.run([])
      end

      errors = collect_errors([])
      # Ensure validation halts before diff/LLM steps attempt to run.
      refute Enum.any?(errors, &String.contains?(&1, "git diff failed"))
      assert Enum.any?(errors, &String.contains?(&1, "missing function"))
    end)
  end

  test "reports config error when deprecated pii_modules key is used" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "priv_signal_score_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    File.cd!(tmp_dir, fn ->
      File.write!("priv-signal.yml", deprecated_yaml())

      Mix.shell(Mix.Shell.Process)
      Mix.Tasks.PrivSignal.Score.run([])

      errors = collect_errors([])
      assert Enum.any?(errors, &String.contains?(&1, "priv-signal.yml is invalid"))
      assert Enum.any?(errors, &String.contains?(&1, "pii_modules is deprecated"))
    end)
  end

  defp sample_yaml do
    """
    version: 1

    pii:
      - module: PrivSignal.Config
        fields:
          - name: email
            category: contact
            sensitivity: medium

    flows:
      - id: config_load_chain
        description: "Config load chain"
        purpose: setup
        pii_categories:
          - config
        path:
          - module: PrivSignal.Config.Loader
            function: load
          - module: PrivSignal.Config.Schema
            function: validate
          - module: PrivSignal.Config
            function: from_map
        exits_system: false
    """
  end

  defp failing_yaml do
    """
    version: 1

    pii:
      - module: PrivSignal.Config
        fields:
          - name: email
            category: contact
            sensitivity: medium

    flows:
      - id: broken_chain
        description: "Broken chain"
        purpose: setup
        pii_categories:
          - config
        path:
          - module: PrivSignal.Config.Loader
            function: load
          - module: PrivSignal.Config
            function: missing_function
        exits_system: false
    """
  end

  defp deprecated_yaml do
    """
    version: 1

    pii_modules:
      - PrivSignal.Config

    flows: []
    """
  end

  defp collect_errors(acc) do
    receive do
      {:mix_shell, :error, [message]} -> collect_errors([message | acc])
      _ -> collect_errors(acc)
    after
      0 -> Enum.reverse(acc)
    end
  end
end
