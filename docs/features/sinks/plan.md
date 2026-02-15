# Sinks and Sources Expansion Delivery Plan

References
- PRD: `docs/features/sinks/prd.md`
- FDD: `docs/features/sinks/fdd.md`

## Scope
Deliver Phase 4 expansion of deterministic scanner coverage from logging-only to five categories: HTTP, controller responses, telemetry/analytics, database reads/writes, and LiveView exposure. Maintain current infer-flow algorithm behavior while expanding node surface area and preserving deterministic output.

## Non-Functional Guardrails
- Determinism: same commit + config => byte-stable findings/nodes/flows.
- Performance: p95 scan runtime regression <= 20% vs current logging-only baseline.
- Reliability: file-level parse/timeout isolation in non-strict mode.
- Security/Privacy: no runtime execution and no value-level PII leakage in logs/artifacts.
- Compatibility: additive output/config changes; existing repos without `scanners` config continue to run.
- Observability: category-level telemetry, AppSignal-ready dimensions, cardinality-safe tags.

## Clarifications (Default Assumptions)
- `CL-01` If `http.internal_domains` and `http.external_domains` both match, `external_domains` wins.
- `CL-02` Controller/LiveView sinks emit only when scanner has explicit PII evidence.
- `CL-03` Unknown/dynamic HTTP destinations default to `external` boundary with lower confidence.
- `CL-04` No DB migrations are required; all changes are config/schema and in-memory contracts.
- `CL-05` `mix priv_signal.scan` remains infer-lockfile oriented and does not introduce a new artifact schema version.

## Dependency Graph (Topological)
1. Phase 0: Contract freeze and fixtures (highest uncertainty burn-down)
2. Phase 1: Config schema + defaults + compatibility
3. Phase 2: Scanner framework refactor (single AST pass, pluggable scanners)
4. Phase 3: Category scanners (HTTP/Controller/Telemetry/Database/LiveView)
5. Phase 4: Infer adapter + flow compatibility updates
6. Phase 5: Observability, resilience, and performance hardening
7. Phase 6: Docs, rollout validation, and release gate

Parallelization policy
- Phase 1 can start once Phase 0 contracts are merged.
- In Phase 3, categories can be implemented in parallel after Phase 2 lands.
- In Phase 5, telemetry instrumentation and perf harness can run in parallel after Phase 4 contract is stable.

## Phase 0: Contract Freeze and Test Harness
Goal
- Lock scanner/finding/node contracts and fixture corpus before refactor to reduce churn and ambiguity.

Tasks
- [x] Build FR-to-test traceability table for `FR-001`..`FR-011` from PRD/FDD.
- [x] Add fixture project files under `test/fixtures/sinks/` covering all five categories with positive/negative examples.
- [x] Add deterministic snapshot fixtures for expected infer lockfile output ordering.
- [x] Add contract tests for new `scanners` config shape and default behavior (pending tags for later-phase activation).
- [x] Add contract tests for candidate->node role mapping (`http`, `http_response`, `telemetry`, `database_read`, `database_write`, `liveview_render`) (pending tags for later-phase activation).

Tests to write/run
- [x] `test/priv_signal/config_schema_scanners_test.exs`
- [x] `test/priv_signal/scan/sinks_contract_test.exs`
- [x] `test/priv_signal/infer/sinks_adapter_contract_test.exs`
- [ ] Command: `mix test test/priv_signal/config_schema_scanners_test.exs test/priv_signal/scan/sinks_contract_test.exs test/priv_signal/infer/sinks_adapter_contract_test.exs`

Definition of Done
- Contract tests exist and fail for unimplemented behavior.
- Fixture matrix covers each category plus cross-category mixed file.

Gate Criteria
- No unmapped FR IDs in traceability table.
- Contract test failures are intentional and documented by phase dependency.

## Phase 1: Config and Schema Foundation
Goal
- Introduce `scanners` config with robust validation and backward-compatible defaults.

Tasks
- [x] Extend `PrivSignal.Config` with scanner category structs/defaults.
- [x] Extend `PrivSignal.Config.Schema` to validate scanner keys/types and inject defaults when omitted.
- [x] Ensure compatibility path for existing configs without `scanners` section.
- [x] Add validation for additional modules/render functions/domain lists/repo modules.
- [x] Add/extend summary/config helpers to expose scanner-enabled state safely.
- [x] [Parallel] Update `mix priv_signal.init` template and README config examples.

Tests to write/run
- [x] `test/priv_signal/config_schema_scanners_test.exs` (positive, malformed, omitted-scanners defaults)
- [x] `test/priv_signal/config_loader_test.exs` scanner YAML parsing coverage
- [x] `test/mix/tasks/priv_signal_init_test.exs` scanner section in generated template
- [x] Command: `mix test test/priv_signal/config_schema_scanners_test.exs test/priv_signal/config_loader_test.exs test/mix/tasks/priv_signal_init_test.exs`

Definition of Done
- Config loads with/without scanner section and produces deterministic defaults.
- Invalid scanner config errors point to exact failing key paths.

Gate Criteria
- All Phase 1 tests pass.
- Existing scan command still runs on fixture config without scanner section.

## Phase 2: Scanner Architecture Refactor (Single AST Pass)
Goal
- Refactor scanning from logging-only into pluggable category scanners executed in one AST parse/traversal per file.

Tasks
- [x] Introduce `PrivSignal.Scan.Scanner` behavior and standardized candidate contract.
- [x] Move logging implementation into `PrivSignal.Scan.Scanner.Logging` preserving existing behavior.
- [x] Update `PrivSignal.Scan.Runner` worker loop to parse each file once and invoke enabled scanner modules.
- [x] Add shared scanner utilities for module/function context normalization and evidence shaping.
- [x] Add per-file cache helpers (alias/module classification lookup maps) for performance.
- [x] Keep deterministic classification/sorting and strict-mode semantics unchanged.

Tests to write/run
- [x] `test/priv_signal/scan/scanner_behavior_test.exs`
- [x] `test/priv_signal/scan/runner_single_parse_test.exs` (assert one parse per file)
- [x] `test/priv_signal/scan/logging_regression_test.exs` (parity with prior logging behavior)
- [x] Command: `mix test test/priv_signal/scan/scanner_behavior_test.exs test/priv_signal/scan/runner_single_parse_test.exs test/priv_signal/scan/logging_regression_test.exs`

Definition of Done
- Runner supports scanner registry and still emits deterministic classified findings.
- Logging category parity established by regression tests.

Gate Criteria
- No regression in existing logging-focused tests.
- Single-AST-pass test passes for mixed fixture files.

## Phase 3: Category Scanner Implementation (Parallel Lanes)
Goal
- Implement five category scanners and config-driven overrides.

Parallel lanes
- Lane A: HTTP + boundary classification
- Lane B: Controller + LiveView exposure
- Lane C: Telemetry + Database read/write

Tasks
- [x] Implement `PrivSignal.Scan.Scanner.HTTP` with known client modules and `additional_modules` overrides.
- [x] Implement domain boundary resolver (`internal_domains`, `external_domains`, unknown defaults).
- [x] Implement `PrivSignal.Scan.Scanner.Controller` with built-in and configured render/send functions.
- [x] Implement `PrivSignal.Scan.Scanner.LiveView` for `assign`, render payloads, and `push_event`.
- [x] Implement `PrivSignal.Scan.Scanner.Telemetry` for telemetry/observability SDK calls and overrides.
- [x] Implement `PrivSignal.Scan.Scanner.Database` for repo read source and write sink detection.
- [x] Normalize role kinds/subtypes and confidence/evidence across all categories.

Tests to write/run
- [x] `test/priv_signal/scan/scanners/http_test.exs`
- [x] `test/priv_signal/scan/scanners/controller_test.exs`
- [x] `test/priv_signal/scan/scanners/liveview_test.exs`
- [x] `test/priv_signal/scan/scanners/telemetry_test.exs`
- [x] `test/priv_signal/scan/scanners/database_test.exs`
- [x] `test/priv_signal/scan/scanners/overrides_test.exs`
- [x] Command: `mix test test/priv_signal/scan/scanners/http_test.exs test/priv_signal/scan/scanners/controller_test.exs test/priv_signal/scan/scanners/liveview_test.exs test/priv_signal/scan/scanners/telemetry_test.exs test/priv_signal/scan/scanners/database_test.exs test/priv_signal/scan/scanners/overrides_test.exs`

Definition of Done
- All five categories emit expected candidate findings under deterministic ordering.
- Override config behavior validated for each category.

Gate Criteria
- All category tests pass.
- AC-aligned fixture scenarios from PRD section 7 pass for FR-002..FR-007.

## Phase 4: Infer Adapter and Flow Compatibility
Goal
- Map expanded findings into infer nodes while keeping flow-building logic stable and backward compatible.

Tasks
- [x] Introduce unified scanner adapter (or extend existing adapter) for multi-category finding->node mapping.
- [x] Preserve NodeNormalizer/NodeIdentity semantics and verify stable IDs.
- [x] Ensure source/sink node types map correctly for database reads/writes.
- [x] Update flow boundary kind handling where required for new sink kinds.
- [x] Add compatibility assertions for artifact schema v1.2 keys and sorting.
- [x] [Parallel] Add golden lockfile snapshots for mixed-category fixture runs.

Tests to write/run
- [x] `test/priv_signal/infer/scanner_adapter_test.exs`
- [x] `test/priv_signal/infer/flow_builder_sinks_test.exs`
- [x] `test/priv_signal/infer/node_identity_sinks_test.exs`
- [x] `test/mix/tasks/priv_signal_scan_sinks_integration_test.exs`
- [x] Command: `mix test test/priv_signal/infer/scanner_adapter_test.exs test/priv_signal/infer/flow_builder_sinks_test.exs test/priv_signal/infer/node_identity_sinks_test.exs test/mix/tasks/priv_signal_scan_sinks_integration_test.exs`

Definition of Done
- Infer output includes new node roles without breaking schema or existing consumers.
- Proto-flow behavior remains unchanged except for expected node-coverage increase.

Gate Criteria
- Flow regression tests pass versus baseline logging fixtures.
- Determinism tests pass across repeated mixed-category runs.

## Phase 5: Observability, Resilience, Security, and Performance
Goal
- Add rollout-grade telemetry, error handling confidence, and performance validation.

Tasks
- [x] Add category-level telemetry events and counters in scan pipeline.
- [x] Add structured summary logs with cardinality-safe metadata.
- [x] Verify strict vs non-strict error behavior across parser/timeouts for new categories.
- [x] Add security checks ensuring no runtime value-level PII leaks into output/logs/telemetry.
- [x] Build perf benchmark harness against baseline fixture and enforce <=20% p95 regression.
- [x] [Parallel] Define AppSignal dashboard/alert checklist in docs.

Tests to write/run
- [x] `test/priv_signal/scan/telemetry_sinks_test.exs`
- [x] `test/priv_signal/scan/resilience_sinks_test.exs`
- [x] `test/priv_signal/scan/security_redaction_sinks_test.exs`
- [x] `test/priv_signal/scan/perf_baseline_test.exs` (or benchmark script under `test/support`)
- [x] Command: `mix test test/priv_signal/scan/telemetry_sinks_test.exs test/priv_signal/scan/resilience_sinks_test.exs test/priv_signal/scan/security_redaction_sinks_test.exs`
- [x] Command: `mix test test/priv_signal/scan/perf_baseline_test.exs --max-failures 1`

Definition of Done
- Telemetry and resilience behavior are validated and documented.
- Performance gate passes against agreed baseline threshold.

Gate Criteria
- Error-rate and telemetry assertions pass in CI.
- Perf test/harness output is attached to PR/release notes.

## Phase 6: Documentation, Rollout, and Final Acceptance
Goal
- Complete rollout docs, acceptance verification, and release readiness.

Tasks
- [x] Update `README.md` scanner documentation for all categories and config overrides.
- [x] Update `docs/features/sinks/prd.md` and `docs/features/sinks/fdd.md` if implementation decisions diverged.
- [x] Add rollout playbook: canary, metrics watchlist, kill-switch, rollback steps.
- [x] Execute full suite and targeted acceptance scenarios mapped to `AC-001`..`AC-010`.
- [x] Produce final FR/AC evidence checklist artifact in feature directory.

Tests to write/run
- [x] Command: `mix test`
- [x] Command: `mix priv_signal.scan --json-path tmp/sinks.lockfile.json` (executed via `mix run -e 'Mix.Tasks.PrivSignal.Scan.run(...)'` in sandbox)
- [x] Manual verification: compare lockfile against golden fixture and confirm deterministic rerun parity.

Definition of Done
- Documentation and spec pack are synchronized with implemented behavior.
- Acceptance criteria are fully evidenced and signed off.

Gate Criteria
- Full test suite passes.
- FR/AC checklist shows complete coverage with no unresolved blockers.

## Final Acceptance Checklist
- [x] All phases complete with gate criteria satisfied.
- [x] Determinism verified via repeat-run tests.
- [x] Performance guardrail met (<=20% p95 regression).
- [x] Category telemetry and alerts validated.
- [x] Rollback/kill-switch verified through config toggles.
- [x] PRD/FDD/Plan all updated and consistent.
