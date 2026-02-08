# Enhanced PII Node Inventory — Delivery Plan

References
- PRD: `docs/features/enhanced_scan/prd.md`
- FDD: `docs/features/enhanced_scan/fdd.md`

## Scope
Deliver a deterministic, schema-versioned PII node inventory for PrivSignal by upgrading scanner output from finding-centric records to canonical nodes. Initial implemented scanner source remains logging sinks, with entrypoint classification scaffolding and inference-agnostic output (no edges). Integrate into `mix priv_signal.infer` while preserving operational compatibility with current `mix priv_signal.scan`.

## Non-Functional Guardrails
- Determinism: identical repo + config + command options => byte-identical sorted node artifact.
- Performance: p50 <= 5s, p95 <= 20s on CI workload up to ~5,000 Elixir files.
- Reliability: parse/read failures are isolated per file and recorded; strict mode can fail run.
- Security/privacy: no runtime PII values in logs, telemetry, or artifacts.
- Observability: lifecycle telemetry for inventory build/run/output + rollout health metrics.
- Backward compatibility: no breakage to existing scan workflows during migration window.

## Clarifications (Default Assumptions)
- `CL-01`: `mix priv_signal.infer` is introduced as canonical command; `mix priv_signal.scan` remains available for one minor release.
- `CL-02`: default infer artifact path is `priv-signal-infer.json`; legacy scan output path remains unchanged.
- `CL-03`: lockfile-style artifact omits non-semantic timestamps from identity-sensitive payload; commit metadata is retained.
- `CL-04`: entrypoint classification is additive and non-blocking (confidence + evidence required).
- `CL-05`: no DB/Ecto migrations are required in this feature scope.
- `CL-06`: scanner coverage expansion beyond logging (HTTP/DB/telemetry/files) is scaffold-only in this release.

## Dependency Graph (Topological Order)
1. Phase 0: Contract Freeze & Risk Burn-Down (highest uncertainty first)
2. Phase 1: Infer Command Surface + Artifact Contract
3. Phase 2: Canonical Node Model + Deterministic Identity
4. Phase 3: Scanner Adapter + Entrypoint Classification
5. Phase 4: Runner/Output Integration + Compatibility


Parallelization strategy
- Phase 0 must complete first.
- In Phase 1, CLI scaffolding and contract test fixture prep can run in parallel.
- In Phase 2, identity module and output schema serializer can run in parallel after node struct contract is fixed.
- In Phase 3, logging adapter work and module classifier work can run in parallel.
- In Phase 4, compatibility wrapper and markdown/json output formatting can run in parallel.


## Phase 0: Contract Freeze & Risk Burn-Down
Goal
- Freeze node schema and determinism rules before broad implementation changes.

Tasks
- [x] Build FR/AC traceability matrix from PRD (`FR-001..FR-014`, `AC-001..AC-009`).
- [x] Define canonical node JSON contract (required fields, enums, optional fields, schema_version semantics).
- [x] Define deterministic identity tuple and explicitly exclude non-semantic fields (lines, timestamps, run env).
- [x] Build fixture set for determinism, line-shift edits, parse failures, and module classification heuristics.
- [x] Add failing contract tests for infer artifact structure and deterministic output guarantees.

Tests to write/run
- [x] Add `test/priv_signal/infer/contract_test.exs`.
- [x] Add `test/priv_signal/infer/determinism_property_test.exs`.
- [x] Command: `mix test test/priv_signal/infer/contract_test.exs test/priv_signal/infer/determinism_property_test.exs`.

Definition of Done
- Node contract and identity rules are documented in tests and accepted by engineering.
- Contract tests fail only for unimplemented functionality, not for ambiguous requirements.

Gate Criteria
- FR/AC mapping has no gaps.
- Contract tests are merged and enforce schema/identity constraints.

## Phase 1: Infer Command Surface + Artifact Contract
Goal
- Introduce infer command and stable artifact envelope without changing scanner semantics yet.

Tasks
- [x] Implement `Mix.Tasks.PrivSignal.Infer` with options: `--strict`, `--json-path`, `--quiet`, `--timeout-ms`, `--max-concurrency`.
- [x] Add infer runner shell (`PrivSignal.Infer.Runner`) that invokes existing scan pipeline as temporary backend.
- [x] Implement infer output envelope (`schema_version`, `tool`, `git`, `summary`, `nodes`, `errors`).
- [x] Add command compatibility path (`mix priv_signal.scan` emits deprecation hint and/or delegates when configured).
- [x] Add docs/help text for infer command and migration notes.

Parallel lanes
- Lane A: CLI task + option parsing.
- Lane B: output envelope + writer path.

Tests to write/run
- [x] Add `test/mix/tasks/priv_signal_infer_test.exs`.
- [x] Add `test/priv_signal/infer/output_envelope_test.exs`.
- [x] Update `test/mix/tasks/priv_signal_scan_test.exs` for compatibility behavior.
- [x] Command: `mix test test/mix/tasks/priv_signal_infer_test.exs test/priv_signal/infer/output_envelope_test.exs test/mix/tasks/priv_signal_scan_test.exs`.

Definition of Done
- `mix priv_signal.infer` runs end-to-end and writes a versioned artifact envelope.
- Compatibility behavior for `scan` is explicit and tested.

Gate Criteria
- Infer command tests pass.
- No regression in existing scan task behavior.

## Phase 2: Canonical Node Model + Deterministic Identity
Goal
- Introduce canonical node structs and deterministic identity generation used by all scanner adapters.

Tasks
- [x] Add `PrivSignal.Infer.Node` and related structs (`EvidenceSignal`, `ModuleClassification`).
- [x] Add `PrivSignal.Infer.NodeNormalizer` for module/function/path canonicalization.
- [x] Add `PrivSignal.Infer.NodeIdentity` for semantic ID generation.
- [x] Implement deterministic sorting policy (`id` primary + canonical tuple secondary).
- [x] Ensure line numbers remain evidence-only fields, never identity inputs.
- [x] Add schema version handling and compatibility checks.

Parallel lanes
- Lane A: node structs + normalizer.
- Lane B: identity + sorting + property tests.

Tests to write/run
- [x] Add `test/priv_signal/infer/node_normalizer_test.exs`.
- [x] Add `test/priv_signal/infer/node_identity_test.exs`.
- [x] Add `test/priv_signal/infer/stable_sort_test.exs`.
- [x] Command: `mix test test/priv_signal/infer/node_normalizer_test.exs test/priv_signal/infer/node_identity_test.exs test/priv_signal/infer/stable_sort_test.exs`.

Definition of Done
- Canonical node model exists and serializes deterministically.
- Identity tests prove unchanged semantic nodes keep the same ID when line numbers shift.

Gate Criteria
- Property/determinism tests pass reliably across repeated runs.

## Phase 3: Scanner Adapter + Entrypoint Classification
Goal
- Convert logging findings into canonical sink nodes and add entrypoint classification scaffolding.

Tasks
- [x] Implement `PrivSignal.Infer.ScannerAdapter.Logging` mapping from existing scanner candidates/findings to node candidates.
- [x] Preserve current logging detection evidence while normalizing role metadata (`role.kind=logger`).
- [x] Implement `PrivSignal.Infer.ModuleClassifier` heuristics (`controller`, `liveview`, `job`, `worker`) with confidence + evidence signals.
- [x] Attach entrypoint context to nodes; optionally emit standalone entrypoint nodes behind config/flag.
- [x] Enforce inference-agnostic behavior (no edge generation).

Parallel lanes
- Lane A: logging adapter.
- Lane B: module classifier heuristics.

Tests to write/run
- [x] Add `test/priv_signal/infer/scanner_adapter_logging_test.exs`.
- [x] Add `test/priv_signal/infer/module_classifier_test.exs`.
- [x] Update `test/priv_signal/scan/logger_test.exs` fixtures for adapter parity.
- [x] Command: `mix test test/priv_signal/infer/scanner_adapter_logging_test.exs test/priv_signal/infer/module_classifier_test.exs test/priv_signal/scan/logger_test.exs`.

Definition of Done
- Logging-based findings are represented as canonical `sink` nodes with required context/evidence.
- Entrypoint classification metadata is present and test-verified for heuristic cases.

Gate Criteria
- AC-001, AC-002, AC-006, AC-007 mappings have passing tests.

## Phase 4: Runner/Output Integration + Compatibility
Goal
- Fully integrate node generation in infer runner and output artifacts; preserve migration compatibility.

Tasks
- [x] Update infer runner to orchestrate file scanning, adapter mapping, normalization, identity, sorting, and writer.
- [x] Add error aggregation for parse/timeouts/worker exits with strict-mode behavior.
- [x] Implement infer JSON renderer for node list and summary counts.
- [x] Implement infer markdown renderer for human review summary.
- [x] Maintain compatibility bridge for legacy scan outputs during migration window.

Parallel lanes
- Lane A: runner orchestration + strict mode.
- Lane B: output rendering modules.
- Lane C: compatibility wrapper behavior.

Tests to write/run
- [x] Add `test/priv_signal/infer/runner_integration_test.exs`.
- [x] Add `test/priv_signal/infer/output_json_test.exs`.
- [x] Add `test/priv_signal/infer/output_markdown_test.exs`.
- [x] Add `test/priv_signal/infer/resilience_test.exs`.
- [x] Command: `mix test test/priv_signal/infer/runner_integration_test.exs test/priv_signal/infer/output_json_test.exs test/priv_signal/infer/output_markdown_test.exs test/priv_signal/infer/resilience_test.exs`.

Definition of Done
- `mix priv_signal.infer` emits complete, deterministic node inventory artifact.
- Strict/non-strict behavior is documented and tested.

Gate Criteria
- AC-003, AC-004, AC-005, AC-008, AC-009 mapped to passing tests.

## QA & Rollout Execution Checklist
- [ ] Given unchanged repo/config, when running infer repeatedly, then artifact is byte-identical.
- [ ] Given logging PII evidence, when infer runs, then sink nodes include `role.kind=logger` and required context.
- [ ] Given module heuristic match, when infer runs, then classification includes confidence and evidence.
- [ ] Given parse failures in non-strict mode, when infer runs, then artifact still produced with structured errors.
- [ ] Given strict mode and any parse failure, when infer runs, then command exits non-zero.
- [ ] Given telemetry collection enabled, when infer runs, then required infer events are emitted without high-cardinality fields.

## Risks & Mitigations
- Identity instability risk.
Mitigation: property tests + contract freeze before implementation.
- Command migration confusion (`scan` vs `infer`).
Mitigation: compatibility period + explicit CLI deprecation messaging.
- Performance regressions on large repos.
Mitigation: bounded concurrency, perf smoke gates, canary monitoring.
- Heuristic classifier noise.
Mitigation: confidence scoring + evidence signals + non-blocking semantics.

## Open Questions
- Should standalone `entrypoint` nodes ship in initial release or remain context-only?
- Should `generated_at` exist in primary artifact or sidecar metadata only?
- What is the exact deprecation timeline for legacy scan finding format?
