defmodule PrivSignal.Scan.Scanners.HTTPTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader
  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Scan.Scanner.HTTP
  alias PrivSignal.Validate.AST

  @fixture_root Path.expand("../../../fixtures/sinks", __DIR__)

  test "detects Req outbound call as HTTP sink" do
    inventory = fixture_inventory()
    path = fixture_path("lib/fixtures/http_client_sink.ex")
    {:ok, ast} = AST.parse_file(path)

    findings =
      HTTP.scan_ast(ast, %{path: path}, inventory,
        scanner_config: PrivSignal.Config.default_scanners()
      )

    assert length(findings) == 1
    finding = hd(findings)

    assert finding.role_kind == "http"
    assert finding.boundary == "external"
    assert finding.sink == "Req.post"
    assert Enum.any?(finding.matched_nodes, &(&1.name == "email"))
  end

  test "classifies configured internal domain as internal boundary" do
    inventory = fixture_inventory()

    path =
      write_tmp_source("""
      defmodule Fixtures.InternalHTTP do
        def call(user) do
          Req.post("https://internal.myapp.com/v1/send", json: %{email: user.email})
        end
      end
      """)

    {:ok, ast} = AST.parse_file(path)

    scanners = PrivSignal.Config.default_scanners()
    scanners = put_in(scanners.http.internal_domains, ["internal.myapp.com"])

    findings = HTTP.scan_ast(ast, %{path: path}, inventory, scanner_config: scanners)

    assert length(findings) == 1
    assert hd(findings).boundary == "internal"
  end

  test "tracks indirect payload provenance through variable and encoding chains" do
    inventory = fixture_inventory()

    path =
      write_tmp_source("""
      defmodule Fixtures.ProvenanceHTTP do
        def call(user) do
          attrs = %{submitted_emails: [user.email]}
          payload = %{event: "invite", payload: attrs}
          encoded = Jason.encode!(payload)
          Req.post("https://api.segment.io/v1/track", body: encoded)
        end
      end
      """)

    {:ok, ast} = AST.parse_file(path)

    findings =
      HTTP.scan_ast(ast, %{path: path}, inventory,
        scanner_config: PrivSignal.Config.default_scanners()
      )

    assert length(findings) == 1
    finding = hd(findings)

    assert Enum.any?(finding.matched_nodes, &(&1.name == "email"))

    assert Enum.any?(finding.evidence, fn evidence ->
             evidence.type == :indirect_payload_ref and
               is_list(evidence.lineage) and
               evidence.match_source in [:exact, :normalized, :alias]
           end)
  end

  defp fixture_inventory do
    {:ok, config} = Loader.load(fixture_path("config/valid_sinks_pii.yml"))
    Inventory.build(config)
  end

  defp fixture_path(relative_path), do: Path.join(@fixture_root, relative_path)

  defp write_tmp_source(source) do
    path =
      Path.join(
        System.tmp_dir!(),
        "priv_signal_http_scanner_#{System.unique_integer([:positive])}.ex"
      )

    File.write!(path, source)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
