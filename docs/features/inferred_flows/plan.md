# Proto Flow Inference v1 (Single-Scope, Same-Unit) — Delivery Plan

## Scope
This plan delivers Proto Flow inference per `docs/features/inferred_flows/prd.md` and `docs/features/inferred_flows/fdd.md` by extending `mix priv_signal.infer` output with deterministic top-level `flows` derived from canonical nodes.

## Non-Functional Guardrails
- Determinism: unchanged input must yield byte-identical `flows`.
- Performance: p95 overhead <= 10% vs infer baseline.
- Reliability: strict mode semantics preserved; contract errors fail fast.
- Security/privacy: no runtime PII values in artifacts, logs, or telemetry metadata.
- Observability: infer run/build/stop telemetry plus output-write telemetry.
- Compatibility: existing `nodes` contract remains consumable; schema version bumped to include `flows`.

## Clarifications (Defaults Applied)
- PRD `privsignal.json` maps to runtime default `priv-signal-infer.json`.
- One sink + many references emits one flow per reference.
- No confidence emission threshold in v1.
- Feature flag kill-switch is `PRIV_SIGNAL_INFER_PROTO_FLOWS_V1`.

## Dependency Order
1. Contract and scoring behavior.
2. Core flow inference engine.
3. Runner/output integration.
4. Telemetry, feature flagging, and operational safety.
5. Perf/determinism tooling and rollout docs.

## Phase 1: Contract Freeze and Test Harness
### Goal
Lock flow contract/identity/scoring rules before implementation.

### Tasks
- [x] Define canonical flow shape and required fields (FR-004/FR-010).
- [x] Define deterministic `psf_` identity tuple and hash strategy (FR-005).
- [x] Define confidence clamp + fixed rounding behavior (FR-006).
- [x] Define boundary mapping rules (FR-007).
- [x] Add flow-focused test scaffolding and fixtures.
- [x] Extend infer contract tests with `flows` validation.

### Tests to Write/Run
```bash
mix test test/priv_signal/infer/flow_identity_test.exs test/priv_signal/infer/flow_scorer_test.exs test/priv_signal/infer/flow_builder_test.exs test/priv_signal/infer/flow_determinism_property_test.exs
```

### Gate Criteria
- [x] Identity/scoring/boundary behavior covered in tests.
- [x] No contract ambiguity blocks implementation.

### Definition of Done
Contract and tests are stable and approved for implementation.

## Phase 2: Core Flow Inference Engine
### Goal
Implement deterministic same-unit flow construction from canonical nodes.

### Tasks
- [x] Implement `PrivSignal.Infer.Flow` struct.
- [x] Implement `PrivSignal.Infer.FlowIdentity`.
- [x] Implement `PrivSignal.Infer.FlowScorer`.
- [x] Implement `PrivSignal.Infer.FlowBuilder` (grouping, anchor rule, one-flow-per-reference, node-id evidence, dedupe/sort).
- [x] Handle missing context safely (skip invalid grouping).
- [x] Implement external boundary mapping helper behavior.
- [x] Add determinism property coverage.

### Tests to Write/Run
```bash
mix test test/priv_signal/infer/flow_builder_test.exs test/priv_signal/infer/flow_identity_test.exs test/priv_signal/infer/flow_scorer_test.exs test/priv_signal/infer/flow_determinism_property_test.exs test/priv_signal/infer/resilience_test.exs
```

### Gate Criteria
- [x] FR-001 through FR-008 and FR-010 covered at module level.
- [x] Determinism verified across input order permutations.

### Definition of Done
Flow builder emits stable, contract-valid in-memory flows.

## Phase 3: Runner and Output Contract Integration
### Goal
Integrate flows into infer pipeline/artifact without breaking node consumers.

### Tasks
- [x] Update `PrivSignal.Infer.Runner` to build flows from nodes.
- [x] Extend infer summary (`flow_count`, `flow_candidate_count`, `flows_hash`, boundary counts).
- [x] Update `PrivSignal.Infer.Contract` (schema `1.2`, `flows` validation/sort).
- [x] Update JSON and markdown infer outputs for flows.
- [x] Preserve strict mode and existing infer error behavior.
- [x] Update integration and mix task tests for flow envelope.

### Tests to Write/Run
```bash
mix test test/priv_signal/infer/runner_integration_test.exs test/priv_signal/infer/output_json_test.exs test/priv_signal/infer/output_envelope_test.exs test/mix/tasks/priv_signal_infer_test.exs
```

### Gate Criteria
- [x] AC-001 to AC-004 and AC-009 validated.
- [x] Existing node consumers continue to work.

### Definition of Done
`mix priv_signal.infer` emits `nodes` + `flows` in a stable schema-validated envelope.

## Phase 4: Telemetry, Flagging, and Operational Safety
### Goal
Add observability and rollout controls needed for safe deployment.

### Tasks
- [x] Emit infer telemetry events for run start/build/stop and output write.
- [x] Include low-cardinality measurements/metadata (`node_count`, `flow_count`, `candidate_count`, boundary counts).
- [x] Add feature flag kill-switch `PRIV_SIGNAL_INFER_PROTO_FLOWS_V1`.
- [x] Add infer telemetry tests.
- [x] Add rollout/rollback runbook.

### Tests to Write/Run
```bash
mix test test/priv_signal/infer/telemetry_test.exs test/priv_signal/infer/runner_integration_test.exs
```

### Gate Criteria
- [x] FR-012 verified by tests.
- [x] Flag on/off behavior verified.

### Definition of Done
Telemetry and kill-switch are live and validated.

## Phase 5: Performance, QA, and Rollout Readiness
### Goal
Finish verification and operations handoff.

### Tasks
- [x] Add deterministic repeat-run/perf helper script (`scripts/bench_infer_flows.sh`).
- [x] Add README updates for infer flows, telemetry, and feature flag.
- [x] Add rollout runbook (`docs/features/inferred_flows/rollout_runbook.md`).
- [x] Run infer-focused and full test suites.

### Tests to Write/Run
```bash
mix test test/priv_signal/infer test/mix/tasks/priv_signal_infer_test.exs
mix test
```

### Gate Criteria
- [x] All automated tests pass.
- [x] Determinism tooling available for canary validation.

### Definition of Done
Feature is ready for canary rollout with test, telemetry, and rollback coverage.

## Cross-Phase Parallelization Matrix
- Lane A: core engine modules (Phase 2).
- Lane B: output/contract/test updates (Phase 3).
- Lane C: telemetry + docs/runbook work (Phase 4/5).

## Final Exit Checklist
- [x] PRD/FDD requirements traced to implementation/tests.
- [x] Phase gates completed.
- [x] `mix compile` clean.
- [x] Infer and full test suites pass.
- [x] Telemetry/flag/rollback docs delivered.
