# Semantic Diff Engine — Delivery Plan

## Scope
This plan implements the Semantic Diff Engine described in `docs/features/semantic_diff/prd.md` and `docs/features/semantic_diff/fdd.md`, producing `mix priv_signal.diff` with semantic change detection, severity scoring, human/JSON output, and CI-ready behavior.

## Non-Functional Guardrails
- Determinism: identical base/candidate inputs produce byte-stable JSON output and stable severity.
- Performance: p50 <= 1.0s, p95 <= 3.0s for target corpus.
- Reliability: >= 99.5% success excluding invalid input.
- Security/privacy: no runtime PII values in logs/output; read-only artifact comparison.
- Runtime model: CLI-only, no long-lived OTP process.

## Clarifications (With Defaults)
- C1: PRD still states ref-to-ref candidate in some sections, while FDD defines hybrid mode (base ref + workspace candidate default).
Default: implement FDD hybrid mode; update PRD during Phase 0 so specs match.
- C2: Artifact path precedence not fully finalized.
Default: `--artifact-path` CLI override > config value (if added) > `priv_signal.lockfile.json`.
- C3: Optional confidence/scanner sections behavior.
Default: warn-and-continue; `--strict` turns missing optional sections into non-zero exit.

## Dependency Graph (Topological)
1. Phase 0 Spec Alignment (unblocks all engineering)
2. Phase 1 CLI/API Contract + Fixtures
3. Phase 2 Artifact Loading + Contract Validation
4. Phase 3 Normalization + Semantic Diff Core
5. Phase 4 Severity + Renderers (human/json)
6. Phase 5 Mix Task Integration + Exit Codes


Parallelization rule: tasks marked `[P]` can be implemented concurrently after their phase dependencies are met.

## Phase 0: Spec Alignment
Goal: Remove ambiguity between PRD/FDD before code changes.

Tasks
- [ ] Update `docs/features/semantic_diff/prd.md` to match hybrid input model from FDD (`--base` required, workspace candidate default, optional `--candidate-ref`).
- [ ] Add/adjust PRD ACs for hybrid mode (workspace candidate path success/failure, candidate-ref mode).
- [ ] Add a short “spec conflict resolved” note in both spec docs.

Tests to write/run
- [ ] Spec QA checklist review (manual): FR-001/FR-010/FR-013 consistency across PRD and FDD.

Commands
- `mix format docs/features/semantic_diff/*.md` (if markdown formatter is configured; otherwise manual lint)

Gate criteria
- PRD and FDD contain no contradictory CLI input model.
- FR and AC mapping is internally consistent.

Definition of Done
- Specs are aligned and implementation-ready; no unresolved blockers from clarifications.

## Phase 1: CLI Contract and Test Fixtures
Goal: Establish command interface and fixture corpus for deterministic implementation.

Tasks
- [x] Add `Mix.Tasks.PrivSignal.Diff` skeleton with option parsing and usage/help text.
- [x] Define canonical CLI options: `--base`, `--candidate-ref`, `--candidate-path`, `--artifact-path`, `--format`, `--include-confidence`, `--strict`, `--output`.
- [x] Create fixture sets for base/candidate artifacts (no-change, add/remove, changed sinks/fields/boundary, malformed JSON, missing artifact).
- [x] [P] Add test helper utilities for building artifact fixtures with deterministic ordering.

Tests to write/run
- [x] Unit tests for option parsing and defaulting rules.
- [x] Unit tests for invalid option combinations (e.g., bad format).

Commands
- `mix test test/priv_signal/*diff*_test.exs`

Gate criteria
- CLI contract is frozen for downstream implementation.
- Fixture corpus covers all FR-003/FR-004 baseline categories and error classes.

Definition of Done
- Stable command/API surface and reusable fixtures are in place.

## Phase 2: Artifact Loader and Contract Validation
Goal: Load base/candidate artifacts from correct sources and enforce schema support.

Tasks
- [x] Implement `PrivSignal.Diff.ArtifactLoader` for base-ref git object load (`git show <base_ref>:<path>`).
- [x] Implement candidate loading from workspace path by default.
- [x] Implement optional candidate-ref loading path.
- [x] Implement `PrivSignal.Diff.Contract` for required fields and supported schema versions.
- [x] Add typed errors for missing artifact, parse failure, unsupported schema, git failures.
- [x] [P] Add `--strict` behavior for optional artifact sections.

Tests to write/run
- [x] Unit tests for loader source selection logic (workspace vs candidate-ref).
- [x] Integration tests for git-load success/failure paths.
- [x] Unit tests for contract validation and unsupported schema behavior.

Commands
- `mix test test/priv_signal/diff/artifact_loader_test.exs`
- `mix test test/priv_signal/diff/contract_test.exs`

Gate criteria
- Artifact provenance is correct and deterministic across input modes.
- Error taxonomy is stable and user-actionable.

Definition of Done
- Loader and contract layer are production-usable and fully tested.

## Phase 3: Normalization and Semantic Diff Core
Goal: Implement noise suppression and semantic classification.

Tasks
- [x] Implement `PrivSignal.Diff.Normalize` canonicalization rules (order-insensitive, metadata suppression).
- [x] Implement `PrivSignal.Diff.Semantic` flow-level comparison:
- [x] Detect `flow_added` and `flow_removed`.
- [x] Detect changed subtypes (`external_sink_added_removed`, `pii_fields_expanded_reduced`, `boundary_changed`).
- [x] Implement deterministic change identity + sorted output ordering.
- [x] [P] Implement optional confidence change comparator behind flag.

Tests to write/run
- [x] Unit tests for each semantic category.
- [x] Property tests for permutation invariance (ordering noise does not change output).
- [x] Golden tests for no-change under formatting/metadata churn.

Commands
- `mix test test/priv_signal/diff/normalize_test.exs`
- `mix test test/priv_signal/diff/semantic_test.exs`
- `mix test test/priv_signal/diff/determinism_property_test.exs`

Gate criteria
- FR-002/FR-003/FR-004/FR-013 behavior proven by tests.
- Determinism checks pass repeatedly.

Definition of Done
- Core diff engine emits correct semantic changes with zero structural-noise regressions.

## Phase 4: Severity Engine and Output Rendering
Goal: Convert semantic changes into reviewer/automation outputs.

Tasks
- [x] Implement `PrivSignal.Diff.Severity` deterministic rule mapping + `rule_id`.
- [x] Implement human renderer grouped by severity, concise <30s-read format.
- [x] Implement JSON renderer contract (`metadata`, `summary`, `changes`).
- [x] [P] Implement confidence-change rendering behavior when enabled.
- [x] Add output schema versioning strategy and stability checks.

Tests to write/run
- [x] Unit tests for each severity rule and priority tie-breaks.
- [x] Snapshot tests for human output formatting.
- [x] JSON schema contract tests for stable machine output.

Commands
- `mix test test/priv_signal/diff/severity_test.exs`
- `mix test test/priv_signal/diff/render_human_test.exs`
- `mix test test/priv_signal/diff/render_json_test.exs`

Gate criteria
- FR-005/FR-006/FR-007 satisfied with deterministic outputs.
- Severity assignment is stable across repeated runs.

Definition of Done
- Output is reviewer-friendly and machine-contract-safe.

## Phase 5: Command Integration, Exit Codes
Goal: Wire full command behavior

Tasks
- [x] Implement `PrivSignal.Diff.Runner` orchestration pipeline.
- [x] Wire `Mix.Tasks.PrivSignal.Diff` end-to-end with exit codes and actionable errors.


Tests to write/run
- [x] Integration tests for CLI success/failure and exit-code matrix.
- [x] Regression test that `diff` never calls `infer` code path.

Commands
- `mix test test/priv_signal/diff/runner_test.exs`
- `mix test test/priv_signal/diff/cli_integration_test.exs`

Gate criteria
- FR-001/FR-009/FR-010/FR-011/FR-013 all verified.

Definition of Done
- `mix priv_signal.diff` is fully operable in local and CI contexts.

## Phase 6: Docs
Goal: Prepare controlled release and operational support.

Tasks
- [ ] Add/update README docs for hybrid command variants and CI examples.

Gate criteria
- Documentation matches shipped CLI behavior.

## Parallel Work Matrix
- After Phase 1:
- Track A: Loader/Contract (Phase 2)
- Track B: Normalize/Semantic (Phase 3, can start with fixture-driven interfaces once loader contract is agreed)
- After Phase 3:
- Track C: Severity/Renderers (Phase 4)
- Track D:  (part of Phase 5) [P]
- After Phase 5:
- Track E: docs (Phase 6)

## Final Exit Criteria (Feature-Level DoD)
- [ ] All FR-001..FR-013 implemented and mapped to automated tests.
- [ ] All AC-001..AC-017 verified (automated where possible, otherwise documented manual verification).
- [ ] `mix priv_signal.diff` supports hybrid input model and ref-to-ref override.
- [ ] Determinism/property/performance gates pass in CI.
- [ ] PRD/FDD/Plan are aligned and committed together.
