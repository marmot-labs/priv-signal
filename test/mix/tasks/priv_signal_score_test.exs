defmodule Mix.Tasks.PrivSignal.ScoreTest do
  use ExUnit.Case

  test "validates priv-signal.yml and reports success" do
    tmp_dir = Path.join(System.tmp_dir!(), "priv_signal_score_#{System.unique_integer([:positive])}")
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

  defp sample_yaml do
    """
    version: 1
    
    pii_modules:
      - MyApp.Accounts.User
    
    flows:
      - id: xapi_export
        description: "User activity exported as xAPI statements"
        purpose: analytics
        pii_categories:
          - user_id
        path:
          - module: MyAppWeb.ActivityController
            function: submit
        exits_system: false
    """
  end
end
