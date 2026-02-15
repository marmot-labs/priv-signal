# Phase 6 FR and AC Evidence Checklist

Date
- 2026-02-15

References
- PRD: `docs/features/sinks/prd.md`
- FDD: `docs/features/sinks/fdd.md`
- Plan: `docs/features/sinks/plan.md`

## Verification Commands
- `mix test`
  - Result: 199 tests, 0 failures, 3 skipped
- `mix run -e 'Mix.Tasks.PrivSignal.Scan.run(["--json-path", "tmp/sinks.lockfile.json", "--quiet"])'`
  - Result: lockfile written to `tmp/sinks.lockfile.json`, nodes emitted, no scan errors

## FR Coverage
- [x] `FR-001` multi-category scanner architecture
  - Evidence: `test/priv_signal/scan/scanner_behavior_test.exs`, `test/priv_signal/scan/runner_single_parse_test.exs`
- [x] `FR-002` HTTP sink detection + boundary
  - Evidence: `test/priv_signal/scan/scanners/http_test.exs`
- [x] `FR-003` controller response sink detection
  - Evidence: `test/priv_signal/scan/scanners/controller_test.exs`
- [x] `FR-004` telemetry sink detection
  - Evidence: `test/priv_signal/scan/scanners/telemetry_test.exs`
- [x] `FR-005` database read/write source/sink detection
  - Evidence: `test/priv_signal/scan/scanners/database_test.exs`
- [x] `FR-006` LiveView exposure sink detection
  - Evidence: `test/priv_signal/scan/scanners/liveview_test.exs`
- [x] `FR-007` scanner config schema + overrides
  - Evidence: `test/priv_signal/config_schema_scanners_test.exs`, `test/priv_signal/scan/scanners/overrides_test.exs`
- [x] `FR-008` stable identity + normalization
  - Evidence: `test/priv_signal/infer/node_identity_sinks_test.exs`, `test/priv_signal/scan/determinism_test.exs`
- [x] `FR-009` proto-flow compatibility
  - Evidence: `test/priv_signal/infer/flow_builder_sinks_test.exs`, `test/priv_signal/infer/runner_integration_test.exs`
- [x] `FR-010` telemetry/counters and observability hooks
  - Evidence: `test/priv_signal/scan/telemetry_sinks_test.exs`, `docs/features/sinks/phase5_observability_checklist.md`
- [x] `FR-011` backward compatibility without `scanners` section
  - Evidence: `test/priv_signal/config_schema_scanners_test.exs`, `test/priv_signal/config_loader_test.exs`

## Acceptance Criteria Coverage
- [x] `AC-001` deterministic outputs and IDs
  - Evidence: `test/priv_signal/scan/determinism_test.exs`, `test/priv_signal/infer/flow_determinism_property_test.exs`
- [x] `AC-002` HTTP sinks emitted with role and evidence
  - Evidence: `test/priv_signal/scan/scanners/http_test.exs`, `test/priv_signal/infer/scanner_adapter_test.exs`
- [x] `AC-003` boundary classification internal/external
  - Evidence: `test/priv_signal/scan/scanners/http_test.exs`
- [x] `AC-004` controller response sink emission
  - Evidence: `test/priv_signal/scan/scanners/controller_test.exs`, `test/priv_signal/infer/scanner_adapter_test.exs`
- [x] `AC-005` telemetry sink emission
  - Evidence: `test/priv_signal/scan/scanners/telemetry_test.exs`, `test/priv_signal/infer/scanner_adapter_test.exs`
- [x] `AC-006` DB read source + write sink emission
  - Evidence: `test/priv_signal/scan/scanners/database_test.exs`, `test/priv_signal/infer/scanner_adapter_test.exs`
- [x] `AC-007` LiveView sink emission
  - Evidence: `test/priv_signal/scan/scanners/liveview_test.exs`, `test/priv_signal/infer/scanner_adapter_test.exs`
- [x] `AC-008` missing scanners config defaults safely
  - Evidence: `test/priv_signal/config_schema_scanners_test.exs`
- [x] `AC-009` infer pipeline compatibility with new roles
  - Evidence: `test/priv_signal/infer/flow_builder_sinks_test.exs`, `test/mix/tasks/priv_signal_scan_sinks_integration_test.exs`
- [x] `AC-010` telemetry metrics present for CI monitoring
  - Evidence: `test/priv_signal/scan/telemetry_sinks_test.exs`

## Manual Spot Checks
- [x] Lockfile generated successfully for sinks implementation path: `tmp/sinks.lockfile.json`
- [x] Full suite passed before sign-off (`mix test`)
