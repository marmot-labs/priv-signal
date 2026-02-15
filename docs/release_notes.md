# Release Notes

## Unreleased

### Rubric V2 Categorical Scoring (Hard Cutover)

- `mix priv_signal.diff` now emits `version: "v2"` with deterministic `events[]` and `summary.events_*` counters.
- `mix priv_signal.score` now accepts only diff `version: "v2"` with `events[]`.
- `mix priv_signal.score` now emits `version: "v2"` and does not emit `points`.
- Added deterministic rubric classifier (`PrivSignal.Score.RubricV2`) with strict decision order:
  - empty => `NONE`
  - any high => `HIGH`
  - else any medium => `MEDIUM`
  - else non-empty => `LOW`
- Legacy score runtime paths and legacy score config keys (`scoring.weights`, `scoring.thresholds` in score mode) are now rejected.
- Added rollout guidance in `docs/features/v2_rubric/rollout_runbook.md`.

### Deterministic Diff-Based Scoring (V1)

- Reworked `mix priv_signal.score` to consume semantic diff JSON artifacts via `--diff` and emit deterministic score JSON output.
- Added deterministic score modules under `PrivSignal.Score.*` (input contract validation, rules, buckets, engine, output writer, optional advisory wrapper).
- Added scoring config support:
  - `scoring.weights`
  - `scoring.thresholds`
  - `scoring.llm_interpretation.*` (disabled by default)
- Removed legacy LLM-first risk-assessment path from score command execution.
- Added score telemetry events for run lifecycle, per-rule hit counts, and advisory outcomes.
- Score command now validates config in score mode and does not require configured `flows`.

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
