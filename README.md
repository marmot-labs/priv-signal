# PrivSignal

PrivSignal is an open-source Elixir CLI that scores privacy risk for PR diffs
using a project-defined map of privacy-relevant data flows.

## Quickstart

```bash
mix priv_signal.init
mix priv_signal.score --base origin/main --head HEAD
```

## Configuration

PrivSignal uses a repo-root `priv-signal.yml` file as the source of truth. Example:

```yaml
version: 1

pii_modules:
  - MyApp.Accounts.User
  - MyApp.Accounts.Author

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
- `[:priv_signal, :git, :diff]`
- `[:priv_signal, :llm, :request]`
- `[:priv_signal, :risk, :assess]`
- `[:priv_signal, :output, :write]`

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
