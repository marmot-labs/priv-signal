# PrivSignal

PrivSignal is an open-source Elixir CLI that scores privacy risk for PR diffs
using a project-defined map of privacy-relevant data flows.

## Quickstart

```bash
mix priv_signal.init
mix priv_signal.validate
mix priv_signal.scan
mix priv_signal.diff --base origin/main
mix priv_signal.score --base origin/main --head HEAD
```

## Configuration

PrivSignal uses a repo-root `priv-signal.yml` file as the source of truth. Example:

```yaml
version: 1

pii:
  - module: MyApp.Accounts.User
    fields:
      - name: email
        category: contact
        sensitivity: medium
      - name: user_id
        category: identifier
        sensitivity: low

flows:
  - id: xapi_export
    description: "User activity exported as xAPI statements"
    purpose: analytics
    pii_categories:
      - user_id
      - ip_address
    path:
      - module: MyAppWeb.ActivityController
        function: submit
      - module: MyApp.Analytics.XAPI
        function: build_statement
      - module: MyApp.Storage.S3
        function: put_object
    exits_system: true
    third_party: "AWS S3"
```

## Validation

Run deterministic flow validation against your codebase:

```bash
mix priv_signal.validate
```

This validation step also runs automatically at the start of `mix priv_signal.score` and will fail fast if any configured flow is invalid.

## Scan Lockfile

Run deterministic static scanning to generate a node inventory artifact:

```bash
mix priv_signal.scan
```

Useful options:

- `--strict`: fail command when any file parse/scan errors occur.
- `--json-path PATH`: write lockfile JSON to a custom path (default: `priv_signal.lockfile.json`).
- `--quiet`: suppress markdown output to stdout.
- `--timeout-ms N`: per-file scan timeout in milliseconds.
- `--max-concurrency N`: max concurrent file workers (bounded internally).

Example:

```bash
mix priv_signal.scan --strict --json-path tmp/priv_signal.lockfile.json --timeout-ms 3000 --max-concurrency 4
```

Scan lockfile schema notes:

- Node keys are currently frozen as `node_type` and `code_context`.
- Proto flow keys are emitted under top-level `flows` when `PRIV_SIGNAL_INFER_PROTO_FLOWS_V1` is enabled (default).
- `schema_version` governs compatibility; any breaking key rename will bump `schema_version`.
- `code_context` contains module/function/file path; line evidence belongs in `evidence`.

Proto-flow feature flag:

- `PRIV_SIGNAL_INFER_PROTO_FLOWS_V1` (`true` by default)
  - `true`: emits inferred `flows` in lockfile artifact
  - `false`: emits `nodes` only (`flows: []`)

## Legacy Scanner Internals

PrivSignal still contains internal scanner modules that feed lockfile generation, but the supported developer command surface is:

```bash
mix priv_signal.scan
mix priv_signal.diff --base <ref>
```

Scanner environment overrides:

- `PRIV_SIGNAL_SCAN_TIMEOUT_MS`
- `PRIV_SIGNAL_SCAN_MAX_CONCURRENCY`

## Migration from `pii_modules`

`pii_modules` is no longer accepted. Convert legacy config to `pii` entries with field metadata.

Before:

```yaml
pii_modules:
  - MyApp.Accounts.User
```

After:

```yaml
pii:
  - module: MyApp.Accounts.User
    fields:
      - name: email
        category: contact
        sensitivity: medium
```

## Environment Variables

- `PRIV_SIGNAL_MODEL_API_KEY`: API key for the model provider (required).
- `PRIV_SIGNAL_SECONDARY_API_KEY`: OpenAI organization key for compatible endpoints (optional).
- `PRIV_SIGNAL_MODEL_URL`: Override the OpenAI-compatible base URL (optional).
- `PRIV_SIGNAL_MODEL`: Model identifier (defaults to `gpt-5`).
- `PRIV_SIGNAL_TIMEOUT_MS`: Connect timeout in milliseconds (optional).
- `PRIV_SIGNAL_RECV_TIMEOUT_MS`: Receive timeout in milliseconds (optional).
- `PRIV_SIGNAL_POOL_TIMEOUT_MS`: Pool checkout timeout in milliseconds (optional).

## GitHub Actions (Example)

```yaml
name: PrivSignal
on:
  pull_request:
jobs:
  priv_signal:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: "1.18"
          otp-version: "27"
      - run: mix deps.get
      - run: mix priv_signal.score --base origin/main --head HEAD
        env:
          PRIV_SIGNAL_MODEL_API_KEY: ${{ secrets.PRIV_SIGNAL_MODEL_API_KEY }}
          PRIV_SIGNAL_SECONDARY_API_KEY: ${{ secrets.PRIV_SIGNAL_SECONDARY_API_KEY }}
```

## Telemetry

PrivSignal emits `:telemetry` events for key steps:

- `[:priv_signal, :config, :load]`
- `[:priv_signal, :validate, :index]`
- `[:priv_signal, :validate, :run]`
- `[:priv_signal, :git, :diff]`
- `[:priv_signal, :llm, :request]`
- `[:priv_signal, :risk, :assess]`
- `[:priv_signal, :output, :write]`
- `[:priv_signal, :scan, :inventory, :build]`
- `[:priv_signal, :scan, :run]`
- `[:priv_signal, :scan, :output, :write]`
- `[:priv_signal, :infer, :run, :start]`
- `[:priv_signal, :infer, :flow, :build]`
- `[:priv_signal, :infer, :run, :stop]`
- `[:priv_signal, :infer, :output, :write]`

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `priv_signal` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:priv_signal, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/priv_signal>.
