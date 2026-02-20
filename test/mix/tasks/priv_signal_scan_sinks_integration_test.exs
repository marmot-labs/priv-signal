defmodule Mix.Tasks.PrivSignal.ScanSinksIntegrationTest do
  use ExUnit.Case

  test "mix priv_signal.scan emits phase4 sink/source role kinds" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "priv_signal_scan_sinks_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    File.cd!(tmp_dir, fn ->
      write_config()
      write_sources()

      Mix.shell(Mix.Shell.Process)
      Mix.Task.reenable("priv_signal.scan")

      Mix.Tasks.PrivSignal.Scan.run(["--json-path", "tmp/sinks.lockfile.json", "--quiet"])

      assert File.exists?("tmp/sinks.lockfile.json")

      lockfile =
        "tmp/sinks.lockfile.json"
        |> File.read!()
        |> Jason.decode!()

      role_kinds =
        lockfile
        |> Map.fetch!("nodes")
        |> Enum.map(fn node -> get_in(node, ["role", "kind"]) end)
        |> Enum.uniq()

      assert "http" in role_kinds
      assert "http_response" in role_kinds
      assert "telemetry" in role_kinds
      assert "database_read" in role_kinds
      assert "database_write" in role_kinds
      assert "liveview_render" in role_kinds
    end)
  end

  defp write_config do
    File.write!(
      "priv-signal.yml",
      """
      version: 1

      prd_nodes:
        - key: demo_user_email
          label: Demo User Email
          class: direct_identifier
          sensitive: true
          scope:
            module: Demo.User
            field: email

      scanners:
        http:
          enabled: true
          additional_modules: []
          internal_domains: []
          external_domains: []
        controller:
          enabled: true
          additional_render_functions: []
        telemetry:
          enabled: true
          additional_modules: []
        database:
          enabled: true
          repo_modules: []
        liveview:
          enabled: true
          additional_modules: []

      flows: []
      """
    )
  end

  defp write_sources do
    File.mkdir_p!("lib")

    File.write!(
      "lib/demo_surfaces.ex",
      """
      defmodule Demo.Repo do
        def get(_schema, _id), do: %Demo.User{email: "x"}
        def insert(data), do: {:ok, data}
      end

      defmodule Demo.User do
        defstruct [:email]
      end

      defmodule Demo.Controller do
        def json(_conn, _payload), do: :ok

        def show(conn, user) do
          json(conn, %{email: user.email})
        end
      end

      defmodule Demo.Live do
        def assign(_socket, _key, _value), do: :ok

        def handle_event(_event, user, socket) do
          assign(socket, :email, user.email)
        end
      end

      defmodule Demo.HTTPClient do
        def send_user(user) do
          Req.post!("https://api.segment.io/track", json: %{email: user.email})
        end
      end

      defmodule Demo.Telemetry do
        def track(user) do
          :telemetry.execute([:demo, :tracked], %{count: 1}, %{email: user.email})
        end
      end

      defmodule Demo.DB do
        def run(user) do
          _ = Demo.Repo.get(Demo.User, 1)
          Demo.Repo.insert(%{email: user.email})
        end
      end
      """
    )
  end
end
