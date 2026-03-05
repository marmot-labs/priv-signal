# Plan: PrivSignal Scanner Recall & Explainability Improvements (`docs/features/improvements/plan.md`)

## Scope
This plan implements the feature defined in:
- [PRD](/Users/darren/dev/priv-signal/docs/features/improvements/prd.md)
- [FDD](/Users/darren/dev/priv-signal/docs/features/improvements/fdd.md)

Target outcomes:
- Controlled normalized + alias PRD matching
- Wrapper-aware DB sink detection (intra-module summaries)
- HTTP payload provenance for prebuilt/encoded payloads
- Staged confidence model (`confirmed`, `probable`, `possible`)
- Deterministic output and fixture-based regression coverage

## Non-Functional Guardrails
- Determinism: identical input/code/config -> byte-stable ordered output.
- Runtime overhead budget: p50 <= +15%, p95 <= +25%, memory <= +20% against baseline fixtures.
- Resilience: parser/provenance failures degrade gracefully (no scan crash).
- Explainability: all non-exact matches include explicit source/lineage.
- No DB schema changes; no long-lived OTP topology changes.
- Source of truth conflict rule: PRD/FDD wins over generic process instructions.

## Clarifications (Assumptions Applied)
- Assumption C1: PRD/FDD unit-test emphasis overrides generic “integration/property required” wording.
  Default: unit-heavy coverage plus one end-to-end fixture-pair regression.
- Assumption C2: Intra-module inference only (no cross-module call graph in this phase).
- Assumption C3: Alias mapping is one-to-one (alias -> canonical PRD token).
- Assumption C4: Added JSON fields are additive only (no breaking schema removals).

## Dependency Graph (Topological)
- P0 -> P1 -> P2 -> P3 -> P4 -> P5
- Parallel lanes inside phases are explicitly marked.
- Tie-break applied: highest uncertainty first (HTTP provenance and confidence harmonization get dedicated gates before final hardening).

## Phase 0: Baseline, Contracts, and Test Harness

Goal: lock current behavior, add baseline fixtures/helpers, and establish deterministic test scaffolding.

Tasks:
- [ ] T0.1 Capture baseline scanner behavior from existing fixtures for comparison snapshots.
- [ ] T0.2 Add shared test helpers for fixture execution + stable output normalization.
- [ ] T0.3 Define canonical confidence/evidence test assertions (single helper API).
- [ ] T0.4 Add deterministic rerun helper (same fixture executed N times; byte-equal assertion).
- [ ] T0.5 Tests: add/adjust helper tests.
- [ ] T0.6 Run tests: `mix test test/priv_signal/scan`.

Parallelizable:
- T0.2 and T0.3 can run in parallel.
- T0.4 depends on T0.2.

Definition of Done:
- Baseline fixtures run from helper API.
- Determinism helper passes locally.
- No production behavior changes yet.

Gate to advance:
- All new/updated tests in `test/priv_signal/scan` pass.
- Baseline snapshot outputs archived for later comparison.

## Phase 1: Token Normalization + Alias Matching

Goal: implement controlled fuzzy matching with explainable match source metadata.

Tasks:
- [ ] T1.1 Add config schema keys for matching normalization and aliases.
- [ ] T1.2 Add config validation rules for alias target existence and collision rejection.
- [ ] T1.3 Implement normalization pipeline (case/snake/camel split, singularization, optional prefix stripping).
- [ ] T1.4 Build normalized and alias indexes in inventory.
- [ ] T1.5 Extend evidence metadata with `match_source` (`exact|normalized|alias`).
- [ ] T1.6 Tests: schema validation tests for valid/invalid alias and normalization config.
- [ ] T1.7 Tests: evidence matching matrix tests (`submitted_emails`, `userEmail`, alias mapped keys).
- [ ] T1.8 Tests: deterministic tie-break test for competing canonical targets.
- [ ] T1.9 Run tests: `mix test test/priv_signal/config test/priv_signal/scan/scanner/evidence_test.exs`.

Parallelizable:
- T1.1 and T1.3 can run in parallel.
- T1.2 depends on T1.1.
- T1.4 depends on T1.3.
- T1.6 can start after T1.1.
- T1.7 depends on T1.4 + T1.5.

Definition of Done:
- Config accepts and validates normalization/alias controls.
- Evidence emits explicit source metadata.
- AC-001 and AC-002 are satisfied.

Gate to advance:
- Phase test suite green.
- No nondeterministic ordering in new evidence arrays.

## Phase 2: Wrapper-Aware Database Sink Detection

Goal: infer DB reads/writes through local wrapper functions without full call graph.

Tasks:
- [ ] T2.1 Add DB wrapper config keys (`wrapper_modules`, `wrapper_functions`) with schema validation.
- [ ] T2.2 Implement deterministic intra-module function summary extraction (`db_read?`, `db_write?`) from `Repo.*` usage.
- [ ] T2.3 Integrate summary lookup into DB scanner callsite analysis.
- [ ] T2.4 Emit inherited wrapper evidence metadata on DB findings.
- [ ] T2.5 Preserve direct `Repo.*` path behavior as baseline.
- [ ] T2.6 Tests: wrapper config validation and negative cases.
- [ ] T2.7 Tests: positive wrapper inference (`Persistence.append_step/2` style).
- [ ] T2.8 Tests: ensure no false inheritance for non-wrapper/non-summary functions.
- [ ] T2.9 Run tests: `mix test test/priv_signal/scan/scanner/database_test.exs test/priv_signal/config`.

Parallelizable:
- T2.1 and T2.2 can run in parallel.
- T2.3 depends on T2.2.
- T2.6 depends on T2.1.
- T2.7/T2.8 depend on T2.3 + T2.4.

Definition of Done:
- Wrapper calls produce DB sink findings when summaries indicate Repo interaction.
- Baseline direct DB sink detection remains unchanged.
- AC-003 is satisfied.

Gate to advance:
- All DB scanner tests pass.
- Deterministic summary output confirmed across repeated runs.

## Phase 3: HTTP Payload Provenance

Goal: recover PRD linkage when payloads are prebuilt/encoded before HTTP sink calls.

Tasks:
- [ ] T3.1 Implement intra-function provenance graph for assignments and variable lineage.
- [ ] T3.2 Support propagation through map/keyword literals, `Map.put`, `Map.merge`, `Jason.encode!`.
- [ ] T3.3 Resolve sink args through lineage graph at HTTP callsite.
- [ ] T3.4 Emit `indirect_payload_ref` evidence with variable chain details.
- [ ] T3.5 Add bounded traversal limits (depth/chain guards) to prevent blowups.
- [ ] T3.6 Tests: lineage propagation matrix across supported builders.
- [ ] T3.7 Tests: unsupported transform fallback behavior.
- [ ] T3.8 Tests: encoded payload positive case.
- [ ] T3.9 Run tests: `mix test test/priv_signal/scan/scanner/http_test.exs`.

Parallelizable:
- T3.1 and T3.5 can run in parallel.
- T3.2 depends on T3.1.
- T3.3 depends on T3.2.
- T3.6 can start after T3.2.
- T3.8 depends on T3.3 + T3.4.

Definition of Done:
- HTTP scanner can attribute PRD refs via provenance when direct sink arg refs are absent.
- New evidence type is emitted with explainable lineage.
- AC-004 is satisfied.

Gate to advance:
- HTTP scanner tests green.
- No timeout regressions on existing fixture corpus.

## Phase 4: Confidence Model Harmonization + Output Contract Updates

Goal: unify confidence tier semantics across new evidence types and preserve output compatibility.

Tasks:
- [ ] T4.1 Update classifier mapping to `confirmed|probable|possible`.
- [ ] T4.2 Define deterministic precedence rules among evidence sources (direct > normalized/alias/provenance > weak heuristics).
- [ ] T4.3 Update JSON and Markdown renderers for new confidence/evidence fields.
- [ ] T4.4 Maintain additive-only output schema compatibility.
- [ ] T4.5 Tests: classifier mapping unit tests for all evidence combinations.
- [ ] T4.6 Tests: renderer snapshot tests for new fields.
- [ ] T4.7 Tests: deterministic output order/IDs unchanged for unchanged fixtures.
- [ ] T4.8 Run tests: `mix test test/priv_signal/scan/classifier_test.exs test/priv_signal/scan/output`.

Parallelizable:
- T4.1 and T4.3 can run in parallel.
- T4.2 depends on T4.1.
- T4.6 depends on T4.3.
- T4.7 depends on T4.1 + T4.3.

Definition of Done:
- Confidence tiers are consistently derived and rendered.
- Existing parsers remain compatible with additive changes.
- AC-005, AC-006, AC-007 are satisfied.

Gate to advance:
- Classifier/output tests pass.
- Snapshot diffs reviewed and accepted.

## Phase 5: End-to-End Fixture Pair, Regression Lock, and Documentation Alignment

Goal: lock previously unreachable branches with one fixture pair and finalize regression protection.

Tasks:
- [ ] T5.1 Add single fixture-pair E2E test demonstrating previously unreachable outcomes now reachable.
- [ ] T5.2 Add pluralized/derived token fixture assertions.
- [ ] T5.3 Add DB wrapper indirection fixture assertions.
- [ ] T5.4 Add HTTP prebuilt/encoded payload fixture assertions.
- [ ] T5.5 Add strict exact-only comparison mode test to measure precision drift.
- [ ] T5.6 Update classification documentation references for new confidence/evidence semantics.
- [ ] T5.7 Full targeted suite run: `mix test test/priv_signal/scan test/priv_signal/config`.
- [ ] T5.8 Full project run: `mix test`.

Parallelizable:
- T5.2, T5.3, and T5.4 can run in parallel.
- T5.1 depends on T5.2 + T5.3 + T5.4.
- T5.6 can run in parallel with T5.5.

Definition of Done:
- One E2E fixture pair covers previously unreachable branch behavior.
- All limitation classes have stable regression tests.
- AC-008 is satisfied.

Gate to complete feature:
- All tests pass (`mix test`).
- Determinism rerun checks pass on new fixtures.
- PRD/FDD traceability matrix complete.

## Phase Ownership and Parallel Staffing Plan

Recommended lane split for parallel developers:
- Developer A: Config + Inventory matching lane (P1, part of P4, docs in P5).
- Developer B: DB wrapper inference lane (P2).
- Developer C: HTTP provenance lane (P3).
- Developer D: Test infrastructure + determinism + snapshots (P0, parts of P4/P5).

Coordination checkpoints:
- Checkpoint 1 after P1/P2/P3 interfaces stabilize (evidence shapes agreed).
- Checkpoint 2 after P4 before fixture lock in P5.
- Final checkpoint after full suite and doc alignment.

## Test Matrix Summary (FR/AC Trace)

- FR-001/002/003 -> T1.6/T1.7/T1.8
- FR-004/005/006 -> T2.6/T2.7/T2.8
- FR-007/008 -> T3.6/T3.7/T3.8
- FR-009/010 -> T4.5/T4.6/T4.7
- FR-011 -> T5.1/T5.2/T5.3/T5.4
- AC-001..AC-008 covered by phase gates above

## Risks and Mitigation Tasks Embedded

- False-positive drift: strict exact-only comparison tests (T5.5).
- Runtime overhead: bounded provenance traversal + timeout regression checks (T3.5, phase gates).
- Contract drift: additive-only renderer assertions + snapshot tests (T4.4, T4.6).
- Determinism regressions: rerun helper + ordering tests each phase (T0.4, T4.7).

## Final Definition of Done (Feature)

- [ ] All phase gates passed in order.
- [ ] Full test suite passing.
- [ ] PRD/FDD requirements and ACs trace to concrete tests.
- [ ] New config keys documented and validated.
- [ ] Confidence/evidence outputs are deterministic and explainable.
- [ ] `docs/features/improvements/plan.md` contains this finalized plan with PRD/FDD references.
