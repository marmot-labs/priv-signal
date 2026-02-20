# Privacy-Relevant Data (PRD) Ontology v1 — Delivery Plan

References:
- PRD: `docs/features/identifiers/prd.md`
- FDD: `docs/features/identifiers/fdd.md`

## Scope
Implement PRD identifier expansion from PII-only to five identifier classes while keeping core scan/diff workflow and runtime behavior largely unchanged. YAML inventory remains authoritative, output/reporting honors new identifier classes, and schema/contracts remain v1-only.

## Implementation Status
- Updated: 2026-02-20
- `mix compile`: passing
- `mix test`: passing (255 tests, 0 failures)
- All phase tasks in this plan are marked complete.

## Non-Functional Guardrails
- Determinism: identical input commit + config must produce byte-identical artifacts.
- Performance: scan p50 <= 8s, p95 <= 20s; diff p50 <= 2s, p95 <= 5s.
- Reliability: file-level failures do not crash the whole run unless strict mode.
- Security/privacy: no raw sensitive values in outputs/logging; keep structural evidence only.
- Versioning: v1-only schemas/contracts; reject non-v1 inputs; no migration/backfill workflow.
- Workflow stability: preserve `mix priv_signal.scan` and `mix priv_signal.diff` behavior.

## Clarifications (with Default Assumptions)
- Clarification 1: Canonical lockfile node field is `data_nodes`.
Default assumption: `data_nodes` is required in v1 outputs for this feature.
- Clarification 2: Existing `config.pii` internals are replaced by `prd_nodes` in config parsing and inventory build.
Default assumption: no compatibility shim is added.
- Clarification 3: Existing telemetry/flag rollout work is out of scope.
Default assumption: no new telemetry, no feature flags, no canary logic.

## Dependency Order
Topological order (risk-first, then maximal parallelism):
1. Phase 1: Contract + config foundations
2. Phase 2: Inventory + scanner/classifier adaptation
3. Phase 3: Infer output + diff semantics
4. Phase 4: Hardening, performance, docs, and final verification

Parallel lanes:
- Lane A: Config/schema/parser work
- Lane B: Scanner/classifier matching work
- Lane C: Infer output contract + diff semantic rule work
- Lane D: Test fixture and integration coverage work

Legend:
- `[P]` = can run in parallel once dependencies are satisfied.
- `[TEST]` = test creation/execution task.

## Phase 1: Contract and Config Foundation
Goal: Establish v1-only PRD schema/contracts and authoritative inventory parsing.

Tasks:
- [x] Implement v1-only config schema for `prd_nodes` and five class enum in `PrivSignal.Config.Schema`.
- [x] Update config structs/parsing in `PrivSignal.Config` to represent PRD nodes and scopes.
- [x] Enforce fail-fast for non-v1 schema/config inputs with explicit errors.
- [x] [P] Update `mix priv_signal.init` template output to emit PRD v1 schema.
- [x] [P] Add/refresh fixtures under `test/fixtures/scan/config/` for valid v1 and invalid non-v1 inputs.
- [x] [TEST] Add/extend config tests: `test/priv_signal/config_schema_test.exs`, `test/priv_signal/config_loader_test.exs`.
- [x] [TEST] Run: `mix test test/priv_signal/config_schema_test.exs test/priv_signal/config_loader_test.exs test/mix/tasks/priv_signal_init_test.exs`.

Definition of Done:
- v1 schema is authoritative in code.
- Non-v1 inputs fail predictably.
- Init task generates valid PRD v1 config.

Gate Criteria:
- All Phase 1 tests pass.
- No remaining code paths accept alternate schema versions.

## Phase 2: Inventory and Scanner/Classifier Adaptation
Goal: Keep existing scan architecture but classify/report expanded identifier classes from YAML inventory.

Tasks:
- [x] Refactor inventory build (`PrivSignal.Scan.Inventory`) from PII-centric fields to PRD node indexing (`key`, `label`, `class`, `scope`, `sensitive`).
- [x] Update matching/classification logic (`PrivSignal.Scan.Classifier` and scanner callsites) to attach PRD class/sensitivity from inventory.
- [x] Ensure AST-discovered non-inventory identifiers do not create new inventory nodes.
- [x] [P] Update scanner adapters or finding shape to carry class-aware evidence metadata.
- [x] [P] Add fixture modules under `test/fixtures/scan/lib/fixtures/` covering all five classes.
- [x] [TEST] Add/extend tests: `test/priv_signal/scan/inventory_test.exs`, `test/priv_signal/scan/classifier_test.exs`, `test/priv_signal/scan/runner_single_parse_test.exs`.
- [x] [TEST] Add integration coverage for unchanged command behavior in `test/mix/tasks/priv_signal_scan_test.exs`.
- [x] [TEST] Run: `mix test test/priv_signal/scan/inventory_test.exs test/priv_signal/scan/classifier_test.exs test/priv_signal/scan/runner_single_parse_test.exs test/mix/tasks/priv_signal_scan_test.exs`.

Definition of Done:
- Scan pipeline reports PRD class-aware findings/nodes from inventory.
- No auto-infer/propose/add behavior exists.
- Command workflow remains unchanged.

Gate Criteria:
- All Phase 2 tests pass.
- AC-aligned behavior for FR-002 through FR-007 is demonstrably covered.

## Phase 3: Infer Output and Diff Semantics
Goal: Preserve scan/diff flow while honoring new identifier classes in artifact and diff trigger outputs.

Tasks:
- [x] Update infer output contract rendering (`PrivSignal.Infer.Output.JSON`, related contract modules) to emit v1 `data_nodes` + `flows` with class/sensitivity/evidence fields.
- [x] Update infer adapters/runner summary paths to align with new identifier typing while keeping execution topology unchanged.
- [x] Update diff normalization/semantic logic (`PrivSignal.Diff.Normalize`, `PrivSignal.Diff.Semantic`, `PrivSignal.Diff.SemanticV2`, `PrivSignal.Diff.Severity`) for class-aware trigger detection.
- [x] [P] Update diff contract validation as needed for new node/flow details (`PrivSignal.Diff.ContractV2` if required by current contract boundary).
- [x] [P] Add/refresh diff fixtures in `test/fixtures/diff/` for inferred attribute export and sensitive linkage scenarios.
- [x] [TEST] Add/extend tests: `test/priv_signal/infer/output_json_test.exs`, `test/priv_signal/infer/runner_integration_test.exs`, `test/priv_signal/diff/semantic_test.exs`, `test/priv_signal/diff/semantic_v2_test.exs`, `test/mix/tasks/priv_signal_diff_v2_integration_test.exs`.
- [x] [TEST] Run: `mix test test/priv_signal/infer/output_json_test.exs test/priv_signal/infer/runner_integration_test.exs test/priv_signal/diff/semantic_test.exs test/priv_signal/diff/semantic_v2_test.exs test/mix/tasks/priv_signal_diff_v2_integration_test.exs`.

Definition of Done:
- Artifacts and diff outputs reflect expanded identifier classes.
- Required trigger types fire correctly.
- Existing command workflow is preserved.

Gate Criteria:
- All Phase 3 tests pass.
- FR-008, FR-012, FR-013 acceptance behavior is covered by integration tests.

## Phase 4: Hardening, Determinism, Performance, and Documentation
Goal: Final quality pass and release-ready implementation package (still pre-release, v1-only).

Tasks:
- [x] Validate determinism end-to-end for scan/infer/diff output ordering and IDs.
- [x] [P] Security/privacy pass to verify evidence redaction expectations and no raw sensitive value leakage.
- [x] [P] Performance baseline verification against PRD targets.
- [x] [TEST] Add/extend determinism/property tests: `test/priv_signal/scan/determinism_test.exs`, `test/priv_signal/infer/determinism_property_test.exs`, `test/priv_signal/diff/determinism_property_test.exs`.
- [x] [TEST] Add/extend resilience tests for strict-mode and parse failure paths.
- [x] [TEST] Run targeted perf/baseline tests (existing relevant perf tests in repo).
- [x] [TEST] Run full suite: `mix test`.
- [x] Update docs consistency across spec pack (`prd.md`, `fdd.md`, this `plan.md`) if implementation details required updates.

Definition of Done:
- All tests pass, including full suite.
- Determinism and performance targets are verified.
- Spec pack and implementation are aligned.

Gate Criteria:
- `mix test` passes with no regressions.
- PRD/FDD acceptance criteria are mapped to passing tests.
- No remaining TODOs for v1 schema-only enforcement.

## Parallel Execution Matrix
- Phase 1:
- Parallel: init template update + fixture creation can run while schema parser code is being implemented.
- Phase 2:
- Parallel: scanner adapter changes and fixture/test authoring can run after inventory structure stabilizes.
- Phase 3:
- Parallel: infer output contract updates and diff semantic fixture authoring can run in parallel after contract shape is agreed.
- Phase 4:
- Parallel: determinism tests, performance checks, and security/logging audit can run concurrently.

## Handoff Notes for Implementer Agent
- Treat PRD/FDD as source of truth: `docs/features/identifiers/prd.md`, `docs/features/identifiers/fdd.md`.
- Do not introduce new schema versions or migration paths.
- Do not alter command workflow semantics; only expand identifier class handling/reporting.
- Keep changes incremental and test-first per phase gates above.
