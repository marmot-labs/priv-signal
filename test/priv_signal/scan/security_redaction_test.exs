defmodule PrivSignal.Scan.SecurityRedactionTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Scan.Output.{JSON, Markdown}
  alias PrivSignal.Scan.Runner

  @fixture_root Path.expand("../../fixtures/scan", __DIR__)

  test "scan artifacts do not leak literal runtime values" do
    {:ok, config} = Loader.load(fixture_path("config/valid_pii.yml"))
    root = make_tmp_dir("scan_security")
    File.mkdir_p!(Path.join(root, "lib"))

    secret_email = "secret@example.com"
    secret_phone = "555-1212"

    File.write!(
      Path.join(root, "lib/leak.ex"),
      """
      defmodule LeakExample do
        require Logger

        def log do
          Logger.info(%{email: "#{secret_email}", phone: "#{secret_phone}"})
          Logger.debug(inspect(params))
        end

        defp params, do: %{token: "super-secret-token"}
      end
      """
    )

    assert {:ok, result} =
             Runner.run(config, source: [root: root, paths: ["lib"]], timeout: 2_000)

    json_text = result |> JSON.render() |> Jason.encode!()
    markdown = Markdown.render(result)

    refute String.contains?(json_text, secret_email)
    refute String.contains?(json_text, secret_phone)
    refute String.contains?(json_text, "super-secret-token")
    refute String.contains?(markdown, secret_email)
    refute String.contains?(markdown, secret_phone)
    refute String.contains?(markdown, "super-secret-token")
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)

  defp make_tmp_dir(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end
end
