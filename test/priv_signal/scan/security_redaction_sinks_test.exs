defmodule PrivSignal.Scan.SecurityRedactionSinksTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Infer.Output.JSON, as: InferJSON
  alias PrivSignal.Infer.Runner

  @fixture_root Path.expand("../../fixtures/sinks", __DIR__)

  test "infer lockfile does not include literal sensitive runtime values" do
    {:ok, config} = Loader.load(fixture_path("config/valid_sinks_pii.yml"))

    root = make_tmp_dir("scan_security_sinks")
    File.mkdir_p!(Path.join(root, "lib"))

    secret_email = "secret-user@example.com"
    secret_token = "tok_super_secret"

    File.write!(
      Path.join(root, "lib/sensitive.ex"),
      """
      defmodule Sensitive do
        def send(user) do
          Req.post!("https://api.segment.io/v1/track", json: %{email: user.email, token: \"#{secret_token}\"})
          :telemetry.execute([:sensitive], %{count: 1}, %{email: user.email, token: \"#{secret_token}\"})
          %{email: \"#{secret_email}\"}
        end
      end
      """
    )

    assert {:ok, result} =
             Runner.run(config,
               source: [root: root, paths: ["lib"]],
               timeout: 2_000,
               max_concurrency: 1
             )

    json = result |> InferJSON.render() |> Jason.encode!()

    refute String.contains?(json, secret_email)
    refute String.contains?(json, secret_token)
    refute String.contains?(json, "secret-user@example.com")
    refute String.contains?(json, "tok_super_secret")
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)

  defp make_tmp_dir(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end
end
