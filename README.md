# PrivSignal

PrivSignal is an open-source Elixir CLI that scores privacy risk for PR diffs
using a project-defined inventory of privacy-relevant identifiers.

## Quickstart

```bash
mix priv_signal.init
mix priv_signal.validate
mix priv_signal.scan
mix priv_signal.diff --base origin/main --format json --output tmp/privacy_diff.json
mix priv_signal.score --diff tmp/privacy_diff.json --output tmp/priv_signal_score.json
```

## Configuration

PrivSignal uses a repo-root `priv_signal.yml` file as the source of truth. Example:

```yaml
version: 1

prd_nodes:
  - key: user_email
    label: User Email
    class: direct_identifier
    sensitive: true
    scope:
      module: MyApp.Accounts.User
      field: email
  - key: user_id
    label: User ID
    class: persistent_pseudonymous_identifier
    sensitive: false
    scope:
      module: MyApp.Accounts.User
      field: user_id
  - key: engagement_score
    label: Engagement Score
    class: inferred_attribute
    sensitive: false
    scope:
      module: MyApp.Analytics.UserProfile
      field: engagement_score

scanners:
  logging:
    enabled: true
    additional_modules: []
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
```

## Validation

Run deterministic flow validation against your codebase:

```bash
mix priv_signal.validate
```

`mix priv_signal.score` no longer runs flow validation; it scores a semantic diff artifact produced by `mix priv_signal.diff`.

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

Phase 4 scanner categories (enabled via `scanners.*.enabled`):

- `logging`: logging sinks (`Logger`, `:logger`, and configured wrapper modules).
- `http`: outbound HTTP client calls (`Req`, `Finch`, `Tesla`, etc.) with boundary classification.
- `controller`: response exposure APIs (`json`, `render`, `send_resp`, etc.).
- `telemetry`: telemetry and analytics exports (`:telemetry.execute`, AppSignal/Sentry/OpenTelemetry patterns).
- `database`: `Repo` reads (`database_read` sources) and writes (`database_write` sinks).
- `liveview`: UI exposure patterns (`assign`, `push_event`, `render`) in LiveView modules.

Category overrides:

- `scanners.logging.additional_modules`: custom logging wrapper modules.
- `scanners.http.additional_modules`: custom HTTP wrapper modules.
- `scanners.http.internal_domains` / `scanners.http.external_domains`: host boundary overrides.
- `scanners.controller.additional_render_functions`: custom response render helpers.
- `scanners.telemetry.additional_modules`: custom analytics/observability wrappers.
- `scanners.database.repo_modules`: explicit repo modules to classify as DB access.
- `scanners.liveview.additional_modules`: custom LiveView module roots.

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

## Migration from `pii_modules` / `pii`

`pii_modules` and `pii` are no longer accepted. Convert legacy config to `prd_nodes` entries.

Before:

```yaml
pii_modules:
  - MyApp.Accounts.User
```

After:

```yaml
prd_nodes:
  - key: user_email
    label: User Email
    class: direct_identifier
    sensitive: true
    scope:
      module: MyApp.Accounts.User
      field: email
```

## Environment Variables

- `PRIV_SIGNAL_MODEL_API_KEY`: API key for optional advisory model interpretation (only required when `scoring.llm_interpretation.enabled: true`).
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
      - run: mix priv_signal.scan
      - run: mix priv_signal.diff --base origin/main --format json --output tmp/privacy_diff.json
      - run: mix priv_signal.score --diff tmp/privacy_diff.json --output tmp/priv_signal_score.json
        env:
          PRIV_SIGNAL_MODEL_API_KEY: ${{ secrets.PRIV_SIGNAL_MODEL_API_KEY }} # optional advisory only
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
