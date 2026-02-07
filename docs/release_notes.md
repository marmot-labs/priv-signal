# Release Notes

## Unreleased

### Scan Feature and PII Config Cutover

- Added `mix priv_signal.scan` for deterministic AST-based scanning of PII-relevant logging sinks.
- Added scanner output artifacts in Markdown and JSON with deterministic finding IDs and confidence labels.
- Added scanner strict mode (`--strict`) plus output/runtime options (`--json-path`, `--quiet`, `--timeout-ms`, `--max-concurrency`).
- Added scan telemetry events:
  - `[:priv_signal, :scan, :inventory, :build]`
  - `[:priv_signal, :scan, :run]`
  - `[:priv_signal, :scan, :output, :write]`
- Enforced `pii` as the only supported PII config source across `validate`, `score`, and `scan`.
- Deprecated key `pii_modules` now hard-fails with migration guidance.
