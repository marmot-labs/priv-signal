defmodule Mix.Tasks.PrivSignal.ValidateTest do
  use ExUnit.Case

  test "mix priv_signal.validate succeeds on valid flows" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "priv_signal_validate_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    File.cd!(tmp_dir, fn ->
      File.write!("priv-signal.yml", passing_yaml())

      Mix.shell(Mix.Shell.Process)
      Mix.Tasks.PrivSignal.Validate.run([])

      assert_received {:mix_shell, :info, ["priv-signal.yml is valid"]}
      assert_received {:mix_shell, :info, ["data flow validation: ok"]}
    end)
  end

  test "mix priv_signal.validate fails on invalid flows" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "priv_signal_validate_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    File.cd!(tmp_dir, fn ->
      File.write!("priv-signal.yml", failing_yaml())

      Mix.shell(Mix.Shell.Process)

      assert_raise Mix.Error, ~r/data flow validation failed/, fn ->
        Mix.Tasks.PrivSignal.Validate.run([])
      end

      errors = collect_errors([])
      assert Enum.any?(errors, &String.contains?(&1, "missing function"))
    end)
  end

  test "mix priv_signal.validate fails when prd module is missing" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "priv_signal_validate_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    File.cd!(tmp_dir, fn ->
      File.write!("priv-signal.yml", missing_prd_yaml())

      Mix.shell(Mix.Shell.Process)

      assert_raise Mix.Error, ~r/data flow validation failed/, fn ->
        Mix.Tasks.PrivSignal.Validate.run([])
      end

      errors = collect_errors([])
      assert Enum.any?(errors, &String.contains?(&1, "missing prd module"))
    end)
  end

  test "mix priv_signal.validate fails with deprecated pii_modules config" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "priv_signal_validate_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    File.cd!(tmp_dir, fn ->
      File.write!("priv-signal.yml", deprecated_yaml())

      Mix.shell(Mix.Shell.Process)

      assert_raise Mix.Error, ~r/data flow validation failed/, fn ->
        Mix.Tasks.PrivSignal.Validate.run([])
      end

      errors = collect_errors([])
      assert Enum.any?(errors, &String.contains?(&1, "pii_modules is unsupported"))
    end)
  end

  defp passing_yaml do
    """
    version: 1

    prd_nodes:
      - key: config_email
        label: Config Email
        class: direct_identifier
        sensitive: true
        scope:
          module: PrivSignal.Config
          field: email

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

    prd_nodes:
      - key: config_email
        label: Config Email
        class: direct_identifier
        sensitive: true
        scope:
          module: PrivSignal.Config
          field: email

    flows:
      - id: config_load_chain
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

  defp missing_prd_yaml do
    """
    version: 1

    prd_nodes:
      - key: missing_email
        label: Missing Email
        class: direct_identifier
        sensitive: true
        scope:
          module: Missing.PII.Module
          field: email

    flows:
      - id: config_load_chain
        description: "Config load chain"
        purpose: setup
        pii_categories:
          - config
        path:
          - module: PrivSignal.Config.Loader
            function: load
          - module: PrivSignal.Config
            function: from_map
        exits_system: false
    """
  end

  defp deprecated_yaml do
    """
    version: 1

    pii_modules:
      - PrivSignal.Config
    prd_nodes: []

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
