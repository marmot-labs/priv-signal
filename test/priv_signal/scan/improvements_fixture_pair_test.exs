defmodule PrivSignal.Scan.ImprovementsFixturePairTest do
  use ExUnit.Case, async: false

  alias PrivSignal.Config.Schema
  alias PrivSignal.Scan.Runner

  test "fixture pair exercises normalized, wrapper, and indirect provenance paths" do
    root = tmp_root()
    base_root = Path.join(root, "base")
    candidate_root = Path.join(root, "candidate")

    File.mkdir_p!(Path.join(base_root, "lib"))
    File.mkdir_p!(Path.join(candidate_root, "lib"))

    File.write!(Path.join(base_root, "lib/sample.ex"), base_source())
    File.write!(Path.join(candidate_root, "lib/sample.ex"), candidate_source())

    {:ok, config} = Schema.validate(config_map())

    assert {:ok, base} =
             Runner.run(config,
               source: [root: base_root, paths: ["lib"]],
               timeout: 2_000,
               max_concurrency: 1
             )

    assert {:ok, candidate} =
             Runner.run(config,
               source: [root: candidate_root, paths: ["lib"]],
               timeout: 2_000,
               max_concurrency: 1
             )

    assert Enum.any?(base.findings, &(&1.sink == "Repo.insert"))
    refute Enum.any?(base.findings, &(&1.sink == "Wrapper.Fixtures.Pair.Persistence.append_step/1"))
    refute Enum.any?(base.findings, &(&1.confidence == :probable))
    assert Enum.any?(candidate.findings, &(&1.confidence == :probable))
    assert Enum.any?(candidate.findings, &(&1.sink == "Wrapper.Fixtures.Pair.Persistence.append_step/1"))

    assert Enum.any?(candidate.findings, fn finding ->
             Enum.any?(finding.evidence, &(&1.type == :indirect_payload_ref))
           end)
  end

  defp config_map do
    %{
      "version" => 1,
      "prd_nodes" => [
        %{
          "key" => "user_email",
          "label" => "User Email",
          "class" => "direct_identifier",
          "sensitive" => true,
          "scope" => %{"module" => "Fixtures.Pair.User", "field" => "email"}
        }
      ],
      "matching" => %{
        "aliases" => %{
          "invitee_email" => "email",
          "primary_email" => "email"
        }
      },
      "scanners" => %{
        "database" => %{
          "enabled" => true,
          "repo_modules" => ["MyApp.Repo"],
          "wrapper_modules" => ["Fixtures.Pair.Persistence"],
          "wrapper_functions" => ["append_step/1"]
        }
      }
    }
  end

  defp base_source do
    """
    defmodule Fixtures.Pair.Persistence do
      alias MyApp.Repo

      def persist(_user), do: :ok
      def append_step(_attrs), do: Repo.insert(%{})
    end
    """
  end

  defp candidate_source do
    """
    defmodule Fixtures.Pair.Persistence do
      alias MyApp.Repo

      def persist(user) do
        append_step(%{invitee_email: user.primary_email})
      end

      def append_step(attrs), do: Repo.insert(attrs)
    end

    defmodule Fixtures.Pair.HTTP do
      def send(user) do
        payload = %{submitted_emails: [user.primary_email]}
        encoded = Jason.encode!(payload)
        Req.post("https://api.segment.io/v1/track", body: encoded)
      end
    end
    """
  end

  defp tmp_root do
    root = Path.join(System.tmp_dir!(), "priv_signal_improvements_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)
    root
  end
end
