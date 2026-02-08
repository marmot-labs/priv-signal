defmodule Mix.Tasks.PrivSignal.InferTest do
  use ExUnit.Case

  test "mix priv_signal.infer succeeds and writes json output" do
    tmp_dir = make_tmp_dir("priv_signal_infer_success")

    File.cd!(tmp_dir, fn ->
      write_valid_config()
      write_logging_source()

      Mix.shell(Mix.Shell.Process)
      Mix.Task.reenable("priv_signal.infer")
      Mix.Tasks.PrivSignal.Infer.run([])

      assert File.exists?("priv-signal-infer.json")
      assert_received {:mix_shell, :info, ["priv-signal.yml is valid"]}
      assert_received {:mix_shell, :info, [message]}
      assert String.contains?(message, "infer nodes:")
    end)
  end

  test "mix priv_signal.infer strict mode fails on parse errors" do
    tmp_dir = make_tmp_dir("priv_signal_infer_strict")

    File.cd!(tmp_dir, fn ->
      write_valid_config()
      write_broken_source()

      Mix.shell(Mix.Shell.Process)
      Mix.Task.reenable("priv_signal.infer")

      assert_raise Mix.Error, ~r/infer failed in strict mode/, fn ->
        Mix.Tasks.PrivSignal.Infer.run(["--strict"])
      end
    end)
  end

  test "mix priv_signal.infer respects --json-path" do
    tmp_dir = make_tmp_dir("priv_signal_infer_json_path")

    File.cd!(tmp_dir, fn ->
      write_valid_config()
      write_logging_source()

      Mix.shell(Mix.Shell.Process)
      Mix.Task.reenable("priv_signal.infer")
      Mix.Tasks.PrivSignal.Infer.run(["--json-path", "tmp/infer.json", "--quiet"])

      assert File.exists?("tmp/infer.json")
    end)
  end

  test "mix priv_signal.infer fails with deprecated config key" do
    tmp_dir = make_tmp_dir("priv_signal_infer_deprecated")

    File.cd!(tmp_dir, fn ->
      File.write!("priv-signal.yml", deprecated_config_yaml())

      Mix.shell(Mix.Shell.Process)
      Mix.Task.reenable("priv_signal.infer")

      assert_raise Mix.Error, ~r/infer failed/, fn ->
        Mix.Tasks.PrivSignal.Infer.run([])
      end

      errors = collect_errors([])
      assert Enum.any?(errors, &String.contains?(&1, "priv-signal.yml is invalid"))
      assert Enum.any?(errors, &String.contains?(&1, "pii_modules is deprecated"))
    end)
  end

  test "README infer example flags work together" do
    tmp_dir = make_tmp_dir("priv_signal_infer_readme_example")

    File.cd!(tmp_dir, fn ->
      write_valid_config()
      write_logging_source()

      Mix.shell(Mix.Shell.Process)
      Mix.Task.reenable("priv_signal.infer")

      Mix.Tasks.PrivSignal.Infer.run([
        "--strict",
        "--json-path",
        "tmp/priv-signal-infer.json",
        "--timeout-ms",
        "3000",
        "--max-concurrency",
        "4",
        "--quiet"
      ])

      assert File.exists?("tmp/priv-signal-infer.json")
    end)
  end

  defp make_tmp_dir(prefix) do
    tmp_dir = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    tmp_dir
  end

  defp write_valid_config do
    File.write!("priv-signal.yml", valid_config_yaml())
  end

  defp write_logging_source do
    File.mkdir_p!("lib")

    File.write!(
      "lib/demo_logger.ex",
      """
      defmodule Demo.Logger do
        require Logger

        def log(user) do
          Logger.info("email=\#{user.email}")
        end
      end
      """
    )
  end

  defp write_broken_source do
    File.mkdir_p!("lib")

    File.write!(
      "lib/broken.ex",
      """
      defmodule Broken do
        def bad(
      end
      """
    )
  end

  defp valid_config_yaml do
    """
    version: 1

    pii:
      - module: Demo.User
        fields:
          - name: email
            category: contact
            sensitivity: high

    flows: []
    """
  end

  defp deprecated_config_yaml do
    """
    version: 1

    pii_modules:
      - Demo.User

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
