# Scoring Feature Delivery Plan

References
- PRD: `docs/features/scoring/prd.md`
- FDD: `docs/features/scoring/fdd.md`

## Scope
Deliver deterministic diff-based scoring for `mix priv_signal.score` that consumes diff JSON and emits score JSON, removes legacy flow-based score runtime logic, and ships **Rubric V1 only** for this feature pack (per FDD section 4.5 compatibility decision). Optional advisory interpretation is non-blocking and does not affect deterministic score fields.

## Non-Functional Guardrails
- Determinism: identical diff JSON + config must produce byte-stable score JSON.
- Performance: score stage target p50 <= 1.5s, p95 <= 5s on CI-class runners.
- Reliability: explicit non-zero failures for invalid/missing/unsupported score input contracts.
- Security/privacy: no runtime PII value leakage in logs, telemetry, or output artifacts.
- Observability: score run lifecycle and rule-hit telemetry must be emitted with low-cardinality metadata.
- Backward compatibility: `mix priv_signal.score` remains the entrypoint while behavior migrates to deterministic diff-driven scoring.

## Clarifications (Default Assumptions)
- `CL-01` This delivery implements **Rubric V1 only** (flow-proxy-backed deterministic scoring), even though node-native Rubric V2 is defined in FDD as future work.
- `CL-02` `mix priv_signal.score` input contract is `--diff <path>`; it does not resolve git refs directly.
- `CL-03` Optional advisory behavior remains disabled by default and cannot change deterministic fields (`score`, `points`, `summary`, `reasons`).
- `CL-04` Legacy flow config can remain in config struct for non-score commands if needed, but score command will not depend on it.
- `CL-05` No DB/Ecto migrations are required in this feature pack.

## Dependency Graph (Topological Order)
1. Phase 0: Spec sync + contract freeze (highest uncertainty burn-down)
2. Phase 1: Score CLI contract and input/output scaffolding
3. Phase 2: Deterministic rubric engine (V1) + bucket logic
4. Phase 3: Config + advisory integration and legacy score path removal
6. Phase 4: CI flow docs, acceptance validation, and release readiness

Parallelization strategy
- Phase 0 is sequential and must finish first.
- In Phase 1, input parser and output renderer can be built in parallel once schema contract is frozen.
- In Phase 2, rule implementation and fixture generation can run in parallel after event-shape contract is fixed.
- In Phase 3, config schema changes and advisory wrapper can run in parallel after engine API is stable.
- Phase 4 is mostly sequential with a parallel docs/release-notes lane.

## Phase 0: Spec Sync and Contract Freeze
Goal
Resolve PRD/FDD ambiguity and lock what “Rubric V1 only” means in testable terms.

Tasks
- [x] Create FR-to-task traceability matrix for `FR-001`..`FR-021` and `SCOR-FR-001`..`SCOR-FR-015`.
- [ ] Update spec pack for explicit V1 scope alignment where needed:
- [x] `docs/features/scoring/prd.md`: annotate that this implementation phase uses V1 flow-proxy signals for deterministic scoring.
- [x] `docs/features/scoring/fdd.md`: ensure compatibility table and V1 decision are authoritative and unambiguous.
- [x] Freeze score input/output schema examples used by tests (`tmp/privacy_diff.json` -> `tmp/priv_signal_score.json`).
- [x] Define rule-id catalog and expected deterministic sort key.

Tests to write/run
- [x] New contract skeleton: `test/priv_signal/score/contract_phase0_test.exs` (pending or failing-first acceptable).
- [x] Command: `mix test test/priv_signal/score/contract_phase0_test.exs`

Definition of Done
- Spec pack states exactly what is in scope for this phase (Rubric V1 only).
- Input/output contracts are frozen for implementation and tests.

Gate Criteria
- No unresolved contradictions between PRD and FDD about V1 vs V2 scoring.
- FR-to-task matrix has no unmapped P0 requirements.

## Phase 1: Score Command Contract and IO Pipeline
Goal
Rewire `mix priv_signal.score` to accept diff JSON input and emit deterministic score JSON artifact skeleton.

Tasks
- [x] Rewrite `Mix.Tasks.PrivSignal.Score` argument parsing to support `--diff`, `--output`, `--quiet`.
- [x] Add `PrivSignal.Score.Input` to load/parse/validate diff JSON contract (V1-compatible shape).
- [x] Add `PrivSignal.Score.Output.JSON` for stable score artifact rendering.
- [x] Add `PrivSignal.Score.Output.Writer` (or adapt existing writer) for deterministic file write path.
- [x] Remove direct git diff loading and LLM-first orchestration from score command path.
- [x] [Parallel] Implement parser and renderer in separate lanes after schema freeze.

Tests to write/run
- [x] New `test/mix/tasks/priv_signal_score_test.exs` cases:
- [x] success path with `--diff` input.
- [x] missing `--diff` and missing file errors.
- [x] malformed JSON/unsupported schema errors.
- [x] output path override behavior.
- [x] New `test/priv_signal/score/input_test.exs` for contract validation.
- [x] New `test/priv_signal/score/output_json_test.exs` for schema and stable field presence.
- [x] Command: `mix test test/mix/tasks/priv_signal_score_test.exs test/priv_signal/score/input_test.exs test/priv_signal/score/output_json_test.exs`

Definition of Done
- `mix priv_signal.score --diff <path> --output <path>` executes deterministically through IO pipeline.
- No git-ref arguments are required by score.

Gate Criteria
- All Phase 1 tests pass.
- Score command no longer calls git-diff loader or LLM in deterministic path.

## Phase 2: Deterministic Rubric V1 Engine
Goal
Implement weighted deterministic rubric (V1), bucket mapping, and reason generation using current diff signals.

Tasks
- [x] Implement `PrivSignal.Score.Engine` with deterministic reduce pipeline.
- [x] Implement `PrivSignal.Score.Rules` with V1 rule map and stable `rule_id`s.
- [x] Implement `PrivSignal.Score.Buckets` (`NONE`, `LOW`, `MEDIUM`, `HIGH`) and threshold handling.
- [x] Implement boundary-tier escalation floor rules supported by V1 available signals.
- [x] Implement summary counters (`nodes_added`, `external_nodes_added`, `high_sensitivity_changes`, `transforms_removed`, `new_external_domains`, `ignored_changes`).
- [x] Ensure unknown/unmapped change types are ignored for points and counted in summary.
- [x] [Parallel] Build fixture matrix for score scenarios while rule implementation proceeds.

Tests to write/run
- [x] New `test/priv_signal/score/rules_test.exs` covering each weighted event.
- [x] New `test/priv_signal/score/buckets_test.exs` for threshold boundaries and escalation floors.
- [x] New `test/priv_signal/score/engine_test.exs` for end-to-end deterministic outputs.
- [x] New `test/priv_signal/score/determinism_property_test.exs` (input permutation invariance).
- [x] Command: `mix test test/priv_signal/score/rules_test.exs test/priv_signal/score/buckets_test.exs test/priv_signal/score/engine_test.exs test/priv_signal/score/determinism_property_test.exs`

Definition of Done
- Rubric V1 scoring produces deterministic `score`, `points`, `summary`, `reasons`.
- `NONE` only appears when scoring-relevant changes are absent.

Gate Criteria
- All Phase 2 tests pass.
- Golden fixture scenarios validate expected outputs:
- empty diff -> `NONE`
- low-signal change -> `LOW`
- additive moderate changes -> `MEDIUM`
- new external PII egress -> `HIGH`

## Phase 3: Config, Advisory, and Legacy Path Removal
Goal
Integrate scoring config overrides, optional advisory layer, and fully remove legacy score codepaths.

Tasks
- [x] Extend `PrivSignal.Config.Schema` for `scoring.weights`, `scoring.thresholds`, `scoring.llm_interpretation.*`.
- [x] Add config validation invariants (positive weights, monotonic thresholds).
- [x] Wire score engine to config overrides.
- [x] Implement `PrivSignal.Score.Advisory` wrapper (optional, default-off, non-blocking).
- [x] Ensure advisory failures do not mutate deterministic fields or fail deterministic scoring.
- [x] Remove score-time usage of `PrivSignal.Risk.Assessor` and legacy `PrivSignal.Analysis.*` path from `mix priv_signal.score`.
- [x] [Parallel] Config schema + advisory wrapper can proceed in parallel once engine interface is stable.

Tests to write/run
- [x] Extend `test/priv_signal/config_schema_test.exs` with `scoring` block cases.
- [x] New `test/priv_signal/score/config_overrides_test.exs`.
- [x] New `test/priv_signal/score/advisory_test.exs`:
- [x] advisory disabled default.
- [x] advisory enabled success.
- [x] advisory enabled failure preserves deterministic fields.
- [x] New regression `test/mix/tasks/priv_signal_score_integration_test.exs` for end-to-end CLI behavior.
- [x] Command: `mix test test/priv_signal/config_schema_test.exs test/priv_signal/score/config_overrides_test.exs test/priv_signal/score/advisory_test.exs test/mix/tasks/priv_signal_score_integration_test.exs`

Definition of Done
- Score runtime is deterministic-first and independent of legacy flow-based risk assessor path.
- Config overrides and advisory behavior are implemented and validated.

Gate Criteria
- All Phase 3 tests pass.
- Grep gate confirms no active `PrivSignal.Risk.Assessor` invocation from score command path.

## Phase 4: CI Integration, Docs, and Final Acceptance
Goal
Finalize CI/CD usage and close acceptance evidence for rollout.

Tasks
- [x] Update command help/docs for new score contract (`--diff` input, JSON output fields).
- [x] Update release notes and migration guidance from legacy score behavior.
- [x] Add CI example workflow sequence:
- [x] `mix priv_signal.scan`
- [x] `mix priv_signal.diff --base ... --format json --output tmp/privacy_diff.json`
- [x] `mix priv_signal.score --diff tmp/privacy_diff.json --output tmp/priv_signal_score.json`
- [x] optional `mix priv_signal.interpret ...`
- [x] Validate FR/AC checklist with evidence references to tests and command outputs.
- [x] [Parallel] docs/release notes can proceed while final acceptance suite runs.

Tests to write/run
- [x] Full suite: `mix test`
- [x] Compile gate: `mix compile --warnings-as-errors`
- [x] Format gate: `mix format --check-formatted`
- [x] E2E smoke commands:
- [x] `mix priv_signal.scan`
- [x] `mix priv_signal.diff --base origin/main --format json --output tmp/privacy_diff.json`
- [x] `mix priv_signal.score --diff tmp/privacy_diff.json --output tmp/priv_signal_score.json`

Definition of Done
- Documentation and CI examples match implemented behavior.
- All acceptance criteria in PRD/FDD are verified with evidence.

Gate Criteria
- All tests and build checks pass.
- PRD/FDD traceability checklist marks all in-scope V1 items complete.

## Cross-Phase Risks and Mitigations
- `R-01` Spec ambiguity (node-native requirement vs V1 flow-proxy reality).
  - Mitigation: Phase 0 spec-sync gate; block implementation until resolved.
- `R-02` Score calibration instability.
  - Mitigation: golden fixture suite and configurable validated weights.
- `R-03` Regression from legacy path removal.
  - Mitigation: targeted integration/regression tests in phases 3 and 5.
- `R-04` Performance degradation on large diffs.
  - Mitigation: phase 4 performance harness and one-pass reduce/sort strategy.

## Final Acceptance Checklist
- [x] `FR-001`/`SCOR-FR-001`: score consumes diff JSON input contract.
- [x] `FR-002`/`SCOR-FR-002`: deterministic path has no LLM dependency.
- [x] `FR-003`/`SCOR-FR-003`: score bucket limited to `NONE|LOW|MEDIUM|HIGH`.
- [x] `FR-004`: `NONE` emitted only for no scoring-relevant changes.
- [x] `FR-005`/`SCOR-FR-005`: weighted rubric implemented (V1 scope).
- [x] `FR-006`: escalation floors applied where signal is available in V1.
- [x] `FR-007`/`SCOR-FR-007`: advisory is non-influential.
- [x] `FR-008`/`SCOR-FR-008`: score JSON includes required deterministic fields.
- [x] `FR-012`/`SCOR-FR-012`: invalid contract fails non-zero.
- [x] `FR-014`/`SCOR-FR-014`: legacy score codepath removed from `mix priv_signal.score`.
- [x] `FR-021`/`SCOR-FR-015`: CI execution order documented and validated.
