# Delivery Plan: Rubric V2 (Categorical, Non-Numeric)

References
- PRD: `docs/features/v2_rubric/prd.md`
- FDD: `docs/features/v2_rubric/fdd.md`

## Scope
Deliver Rubric V2 scoring for PrivSignal by introducing a versioned diff event contract (`version: v2`) and a categorical score engine that outputs only `NONE|LOW|MEDIUM|HIGH` with deterministic reasons and summary counts, while removing legacy V1 scoring code and behavior.

## Non-Functional Guardrails
- Determinism: identical diff artifact + config must produce byte-stable score JSON.
- Performance: score stage p50 <= 1.0s, p95 <= 3.0s, p99 <= 5.0s.
- Memory: score stage p95 <= 200MB.
- Reliability: fail closed on invalid contract; advisory remains non-fatal.
- Security/privacy: no runtime PII values in log/output.
- Legacy removal: no v1 scoring runtime/config path remains after cutover.

## Clarifications (Default Assumptions)
- `CL-01` This repo is CLI-first; LiveView/LTI/tenant concerns are not active runtime paths for this feature.
- `CL-02` Rubric V2 is the only supported scoring approach after implementation.
- `CL-03` Diff v2 will emit `events[]`; score v2 reads only `events[]`.
- `CL-04` Score output will not include `points`; any in-repo parser must be updated in the same change.
- `CL-05` Unknown valid event types are warning-only in non-strict mode and fail in strict mode.

## Dependency Graph (Topological)
1. Phase 0: Contract freeze and fixture strategy (highest uncertainty burn-down)
2. Phase 1: Diff v2 event production + schema contract
3. Phase 2: Score input/output v2 contracts + hard cutover plumbing
4. Phase 3: Rubric V2 categorical engine
5. Phase 4: Security hardening + legacy-path removal verification
6. Phase 5: E2E, performance checks, docs, and release readiness

Parallelization rules
- Phase 0 is sequential and blocks all implementation phases.
- In Phase 1, semantic-event builder and JSON renderer updates can be parallel once taxonomy is frozen.
- In Phase 2, config plumbing and output renderer changes can be parallel after input contract is fixed.
- In Phase 3, rubric classifier implementation and fixture/golden-output generation can be parallel.

## Phase 0: Spec Sync and Contract Freeze
Goal
- Remove ambiguity from PRD/FDD and lock the exact v2 diff/score JSON contracts and rule catalog.

Tasks
- [x] Produce FR traceability table for `RV2-FR-001..010` mapped to code modules and tests.
- [x] Freeze v2 event taxonomy and rule id catalog in `docs/features/v2_rubric/fdd.md` appendix.
- [x] Define deterministic sort keys for `events[]` and `reasons[]`.
- [x] Define supported score input matrix: only diff `version: v2` is accepted.
- [x] Add failing-first contract tests skeleton:
- [x] `test/priv_signal/diff/contract_v2_test.exs`
- [x] `test/priv_signal/score/contract_v2_test.exs`

Tests to write/run
- [x] `mix test test/priv_signal/diff/contract_v2_test.exs`
- [x] `mix test test/priv_signal/score/contract_v2_test.exs`

Definition of Done
- Contract fields, required/optional semantics, and deterministic ordering are unambiguous and documented.
- Failing-first contract tests exist and encode the frozen contract.

Gate Criteria
- No unresolved PRD/FDD contradictions.
- Every `RV2-FR-*` has at least one planned test.

## Phase 1: Diff V2 Event Contract Implementation
Goal
- Emit deterministic node/edge-native diff events (`version: v2`) with stable `event_id`.

Tasks
- [x] Implement `PrivSignal.Diff.SemanticV2` for node/edge event generation.
- [x] Add stable `event_id` generator and collision tests.
- [x] Update `PrivSignal.Diff.Render.JSON` to render v2 shape (`events[]`, v2 summary counters).
- [x] Add strict contract validation for v2 events in diff pipeline.
- [x] Remove legacy score-oriented diff payload assumptions not needed by v2.
- [x] [Parallel] Build fixture corpus:
- [x] high: new external egress, transform removal, new vendor destination
- [x] medium: new internal sink, boundary tier increase, confidence+exposure expansion
- [x] low: residual privacy-relevant changes

Tests to write/run
- [x] `test/priv_signal/diff/semantic_v2_test.exs`
- [x] `test/priv_signal/diff/render_json_v2_test.exs`
- [x] `test/priv_signal/diff/event_id_determinism_test.exs`
- [x] `test/mix/tasks/priv_signal_diff_v2_integration_test.exs`
- [x] `mix test test/priv_signal/diff/semantic_v2_test.exs test/priv_signal/diff/render_json_v2_test.exs test/priv_signal/diff/event_id_determinism_test.exs test/mix/tasks/priv_signal_diff_v2_integration_test.exs`

Definition of Done
- `mix priv_signal.diff` can emit valid `version: v2` JSON with deterministic `events[]`.
- Event taxonomy is represented by machine-readable fields required by score v2.

Gate Criteria
- All Phase 1 tests pass.
- Golden fixtures prove stable output ordering over repeated runs.

## Phase 2: Score V2 IO Contract and Hard Cutover
Goal
- Prepare score command to ingest diff v2 events and emit v2 schema while deleting v1 score runtime paths.

Tasks
- [x] Update `PrivSignal.Score.Input` to validate and normalize diff `version: v2` event payloads.
- [x] Remove v1 score command routing and delete score-time rubric toggle logic.
- [x] Update `Mix.Tasks.PrivSignal.Score` to require v2 contract only.
- [x] Update `PrivSignal.Score.Output.JSON` to emit `version: v2` and remove `points`.
- [x] Add explicit unsupported-contract errors for legacy score input/config paths.
- [x] [Parallel] Update CLI/help text and error messaging for v2-only behavior.

Tests to write/run
- [x] `test/priv_signal/config_schema_score_legacy_rejection_test.exs`
- [x] `test/priv_signal/score/input_v2_test.exs`
- [x] `test/priv_signal/score/output_json_v2_test.exs`
- [x] `test/mix/tasks/priv_signal_score_v2_contract_test.exs`
- [x] `mix test test/priv_signal/config_schema_score_legacy_rejection_test.exs test/priv_signal/score/input_v2_test.exs test/priv_signal/score/output_json_v2_test.exs test/mix/tasks/priv_signal_score_v2_contract_test.exs`

Definition of Done
- Score command correctly parses diff v2 and outputs v2 schema without points.
- Legacy score codepaths/config are removed from the runtime path.

Gate Criteria
- All Phase 2 tests pass.
- Contract tests verify explicit failures for legacy score inputs and malformed events.

## Phase 3: Rubric V2 Categorical Engine
Goal
- Implement deterministic categorical classification and reason generation per PRD decision order.

Tasks
- [x] Implement `PrivSignal.Score.RubricV2` rule mapping from events to `high|medium|low`.
- [x] Update `PrivSignal.Score.Engine` with strict decision order:
- [x] empty diff -> `NONE`
- [x] any high -> `HIGH`
- [x] else any medium -> `MEDIUM`
- [x] else non-empty -> `LOW`
- [x] Emit deterministic triggering `reasons[]` (event_id + rule_id) and summary counters.
- [x] Ensure unknown taxonomy handling matches strict/non-strict policy.
- [x] [Parallel] Create golden score fixtures for each acceptance scenario.

Tests to write/run
- [x] `test/priv_signal/score/rubric_v2_rules_test.exs`
- [x] `test/priv_signal/score/engine_v2_test.exs`
- [x] `test/priv_signal/score/decision_order_v2_test.exs`
- [x] `test/priv_signal/score/determinism_v2_property_test.exs`
- [x] `mix test test/priv_signal/score/rubric_v2_rules_test.exs test/priv_signal/score/engine_v2_test.exs test/priv_signal/score/decision_order_v2_test.exs test/priv_signal/score/determinism_v2_property_test.exs`

Definition of Done
- Rubric v2 produces only `NONE|LOW|MEDIUM|HIGH`.
- Output includes deterministic reasons and summaries with no numeric points.

Gate Criteria
- All Phase 3 tests pass.
- Acceptance criteria from `docs/features/v2_rubric/prd.md` are satisfied by fixture evidence.

## Phase 4: Security, and Legacy-Path Removal Hardening
Goal
- Finalize logging redaction, and enforce that no legacy score behavior remains.

Tasks
- [x] Add structured logs for score decisions and contract failures with redaction assertions.
- [x] Add grep/static checks proving no legacy score modules are referenced by score runtime.
- [x] Add migration note for downstream parsers (`points` removed).

Tests to write/run
- [x] `test/priv_signal/score/security_redaction_v2_test.exs`
- [x] `test/priv_signal/score/legacy_contract_rejection_test.exs`
- [x] `mix test test/priv_signal/score/security_redaction_v2_test.exs test/priv_signal/score/legacy_contract_rejection_test.exs`

Definition of Done
- Security/privacy constraints are enforced by tests.
- Legacy score paths are removed and verified absent.

Gate Criteria
- All Phase 4 tests pass.
- Static/runtime checks prove v1 scoring is unsupported.

## Phase 5: End-to-End Validation, Performance, and Release Readiness
Goal
- Prove full pipeline correctness and production readiness.

Tasks
- [x] End-to-end fixture pipeline tests (`scan -> diff(v2) -> score(v2)`).
- [x] Add performance benchmark test/job for >=10k v2 events against latency and memory budgets.
- [x] Run full suite and quality gates.
- [x] Update `docs/features/v2_rubric/{prd.md,fdd.md,plan.md}` status checklists with evidence links.
- [x] Update release notes with migration guidance and config examples.
- [x] [Parallel] Prepare rollout instructions for one-way cutover.

Tests to write/run
- [x] `test/mix/tasks/priv_signal_v2_e2e_test.exs`
- [x] `test/priv_signal/score/perf_v2_baseline_test.exs`
- [x] `mix test`
- [x] `mix compile --warnings-as-errors`
- [x] `mix format --check-formatted`
- [x] smoke commands:
- [x] `mix priv_signal.scan` (verified in `test/mix/tasks/priv_signal_v2_e2e_test.exs`)
- [x] `mix priv_signal.diff --base origin/main --format json --output tmp/privacy_diff_v2.json` (equivalent verified with `--base HEAD` in `test/mix/tasks/priv_signal_v2_e2e_test.exs`)
- [x] `mix priv_signal.score --diff tmp/privacy_diff_v2.json --output tmp/priv_signal_score_v2.json` (verified in `test/mix/tasks/priv_signal_v2_e2e_test.exs`)

Definition of Done
- Full pipeline passes acceptance, determinism, and performance gates.
- Documentation and cutover playbook are complete and consistent with behavior.

Gate Criteria
- All checks pass with no regressions.
- Sign-off from engineering owner on one-way cutover readiness.

## Final Acceptance Checklist
- [x] `RV2-FR-001` score consumes semantic diff and outputs valid category.
- [x] `RV2-FR-002` empty diff -> `NONE`.
- [x] `RV2-FR-003` any HIGH event -> `HIGH`.
- [x] `RV2-FR-004` no HIGH + any MEDIUM -> `MEDIUM`.
- [x] `RV2-FR-005` non-empty without HIGH/MEDIUM -> `LOW`.
- [x] `RV2-FR-006` deterministic triggering reasons emitted.
- [x] `RV2-FR-007` no `points` field in score v2 output.
- [x] `RV2-FR-008` diff emits required node/edge-native metadata.
- [x] `RV2-FR-009` stable `event_id` semantics verified.
- [x] `RV2-FR-010` repeated runs are byte-stable.
