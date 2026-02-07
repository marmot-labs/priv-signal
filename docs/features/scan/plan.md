# Scan Feature Delivery Plan

References
- PRD: `docs/features/scan/prd.md`
- FDD: `docs/features/scan/fdd.md`

## Scope
Deliver the PII inventory + logging scanner feature with a hard config cutover to `pii` as the only supported PII source for all commands (`scan`, `validate`, `score`). Implement deterministic AST-based scanning for logging sinks, evidence-rich findings, JSON/Markdown reporting, and telemetry.

## Non-Functional Guardrails
- Deterministic outputs for identical code + config inputs.
- CI-suitable runtime and bounded concurrency.
- Strict separation of config/schema errors vs scan findings.
- No runtime PII value leakage in logs or artifacts.
- Single canonical PII normalization path reused by scanner and existing commands.
- Advisory scanner behavior by default (non-blocking), with explicit strict mode for parse failures.

## Clarifications (Default Assumptions)
- `CL-01` `pii_modules` is rejected immediately after cutover with actionable migration error text.
- `CL-02` `mix priv_signal.scan` is a dedicated command in v1; `score` integration remains optional follow-up.
- `CL-03` Parse/index failures are best-effort by default for scanner with `--strict` opt-in.
- `CL-04` Wrapper logger functions are out-of-scope for v1 unless direct alias to `Logger`/`:logger` is statically obvious.
- `CL-05` Multi-tenant boundary for this CLI is repository root; no tenant context switching is required.

## Dependency Graph (Topological Order)
1. Phase 0: Contracts and fixture harness (highest uncertainty burn-down)
2. Phase 1: Config cutover foundation (`pii` only) and existing workflow alignment
3. Phase 2: Inventory and AST sink detection core
4. Phase 3: Scanner orchestration, CLI, and report outputs
5. Phase 4: Observability, resilience, security hardening, and performance checks
6. Phase 5: Documentation, migration guidance, and release gate validation

Parallelization strategy
- Phase 0 and 1 are mostly sequential due schema contract coupling.
- In Phase 2, inventory normalization and AST sink detection can run in parallel after core schema model is merged.
- In Phase 3, CLI wiring and output rendering can run in parallel after runner contracts are stable.
- In Phase 4, telemetry and performance tasks can run in parallel once scanner orchestration is complete.

## Phase 0: Contract Freeze and Test Harness
Goal
Define and lock behavior for config cutover, scanner output schema, and acceptance fixtures before implementation churn.
Estimate
- 1.0-1.5 dev-days
Owner lane
- QA/Contract lane

Tasks
- [ ] Build FR-to-test traceability matrix from PRD/FDD (`SCN-FR-01`..`SCN-FR-09`).
- [ ] Create scanner fixture sources under `test/fixtures/scan/` covering confirmed, possible, and negative cases.
- [ ] Create config fixture variants: valid `pii`, malformed `pii`, and deprecated `pii_modules`.
- [ ] Add failing contract tests for config cutover expectations.
- [ ] Add failing contract tests for scanner JSON and Markdown shape (snapshot or exact map assertions).

Tests to write/run
- [ ] `test/priv_signal/config_schema_test.exs`: add `pii` required + `pii_modules` rejected cases.
- [ ] `test/mix/tasks/priv_signal_score_test.exs`: add failure assertion for deprecated key.
- [ ] New `test/mix/tasks/priv_signal_scan_test.exs`: command contract skeleton.
- [ ] Command: `mix test test/priv_signal/config_schema_test.exs test/mix/tasks/priv_signal_score_test.exs test/mix/tasks/priv_signal_scan_test.exs`

Definition of Done
- Contract tests exist and clearly encode cutover behavior and expected scanner artifact schema.
- Fixture set is sufficient to cover acceptance criteria scenarios.

Gate Criteria
- All new/updated contract tests pass or are explicitly marked pending with TODO IDs tied to Phase 1/2 tasks.
- FR-to-test matrix is complete with no unmapped FR IDs.

## Phase 1: Config Cutover and Existing Command Alignment
Goal
Implement `pii` as the only supported PII config source and align `validate`/`score` to canonical normalized PII data.
Estimate
- 2.0-3.0 dev-days
Owner lane
- Config/Core lane

Tasks
- [x] Update `PrivSignal.Config` structs to represent `pii` declarations and remove runtime reliance on `pii_modules`.
- [x] Update `PrivSignal.Config.Schema` to require `pii` and reject `pii_modules` with migration guidance.
- [x] Add `PrivSignal.Config.PII` normalization module for module list, field metadata, and key tokens.
- [x] Update `PrivSignal.Config.Summary` to include normalized `pii` data for score prompts.
- [x] Update `PrivSignal.Validate.run/2` to validate PII modules from normalized `pii` declarations.
- [x] Update `Mix.Tasks.PrivSignal.Init` sample config to emit only `pii`.
- [x] Update existing CLI error messaging to clearly distinguish schema migration failures.
- [x] [Parallel] Extend loader/schema tests and validate/score tests once core schema merge is in place.

Tests to write/run
- [x] `test/priv_signal/config_schema_test.exs`: positive and negative matrix for `pii` entries.
- [x] `test/priv_signal/config_loader_test.exs`: parsing of new YAML structure.
- [x] `test/priv_signal/validate_test.exs`: PII module existence checks from `pii` declarations.
- [x] `test/mix/tasks/priv_signal_validate_test.exs`: migration failure output for deprecated key.
- [x] `test/mix/tasks/priv_signal_score_test.exs`: score fails fast on invalid/deprecated config.
- [x] `test/mix/tasks/priv_signal_init_test.exs`: init template contains `pii`, not `pii_modules`.
- [x] Command: `mix test test/priv_signal/config_schema_test.exs test/priv_signal/config_loader_test.exs test/priv_signal/validate_test.exs test/mix/tasks/priv_signal_validate_test.exs test/mix/tasks/priv_signal_score_test.exs test/mix/tasks/priv_signal_init_test.exs`

Definition of Done
- All commands (`validate`, `score`) consume canonical `pii` data path.
- Deprecated `pii_modules` configurations fail with actionable migration guidance.
- No code path reads `pii_modules` as active input.

Gate Criteria
- All Phase 1 tests pass.
- Grep check confirms no active schema acceptance of `pii_modules` remains (except in migration-error text/tests/docs).
- `mix priv_signal.validate` works with valid `pii` config and fails with deprecated config.

## Phase 2: Inventory and AST Logging Detection Core
Goal
Implement deterministic scanner core: inventory build, logging sink detection, evidence extraction, and classification.
Estimate
- 3.0-4.0 dev-days
Owner lane
- Scanner core lane

Tasks
- [x] Implement `PrivSignal.Scan.Inventory` for normalized module/field/key lookup maps.
- [x] Implement `PrivSignal.Scan.Source` deterministic source enumeration.
- [x] Implement `PrivSignal.Scan.Logger` AST traversal with module/function/arity context capture.
- [x] Implement sink matching for `Logger.<level>`, `Logger.log/2`, `:logger.*`.
- [x] Implement evidence extraction for direct field access and map/keyword key matches.
- [x] Implement `PrivSignal.Scan.Classifier` for `confirmed_pii` and `possible_pii` with sensitivity summary.
- [x] Implement deterministic finding fingerprint/id strategy and stable sorting contract.
- [x] [Parallel] Inventory module work and AST detector work can proceed concurrently after shared finding struct contract is frozen.

Tests to write/run
- [x] New `test/priv_signal/scan/inventory_test.exs`.
- [x] New `test/priv_signal/scan/logger_test.exs` for sink and evidence matching.
- [x] New `test/priv_signal/scan/classifier_test.exs` for confidence and sensitivity classification.
- [x] New `test/priv_signal/scan/determinism_test.exs` for stable IDs/order across repeated runs.
- [x] Command: `mix test test/priv_signal/scan/inventory_test.exs test/priv_signal/scan/logger_test.exs test/priv_signal/scan/classifier_test.exs test/priv_signal/scan/determinism_test.exs`

Definition of Done
- Scanner core detects target logging sinks and emits evidence-rich findings with deterministic ordering.
- Classification conforms to PRD acceptance semantics (`confirmed_pii`, `possible_pii`).

Gate Criteria
- All Phase 2 tests pass.
- Repeated-run determinism test passes at least 10 repeated invocations in one test run.

## Phase 3: Runner, CLI, and Report Outputs
Goal
Deliver executable scanner command and artifacts with clear separation of findings vs operational errors.
Estimate
- 2.0-3.0 dev-days
Owner lane
- Runtime/CLI lane

Tasks
- [x] Implement `PrivSignal.Scan.Runner` with `Task.Supervisor.async_stream_nolink` bounded concurrency.
- [x] Implement parse/timeout error handling and strict-mode behavior.
- [x] Add `Mix.Tasks.PrivSignal.Scan` with options (`--strict`, `--json-path`, `--quiet` as applicable).
- [x] Implement scanner output modules (`PrivSignal.Scan.Output.JSON`, `PrivSignal.Scan.Output.Markdown`).
- [x] Implement output write path and terminal summary lines.
- [x] Ensure findings include module/function/arity/file/line/sink/matched fields/sensitivity/confidence.
- [x] [Parallel] CLI option parsing and output renderer implementation can run in parallel once runner result contract is fixed.

Tests to write/run
- [x] New `test/mix/tasks/priv_signal_scan_test.exs`: success, strict failure, deprecated config error, output path handling.
- [x] New `test/priv_signal/scan/output_json_test.exs`.
- [x] New `test/priv_signal/scan/output_markdown_test.exs`.
- [x] New integration `test/priv_signal/scan_runner_integration_test.exs` using fixture project files.
- [x] Command: `mix test test/mix/tasks/priv_signal_scan_test.exs test/priv_signal/scan/output_json_test.exs test/priv_signal/scan/output_markdown_test.exs test/priv_signal/scan_runner_integration_test.exs`

Definition of Done
- `mix priv_signal.scan` produces deterministic JSON and Markdown outputs from fixture repositories.
- Config errors are reported distinctly from scan findings.

Gate Criteria
- All Phase 3 tests pass.
- Manual smoke run: `mix priv_signal.scan` on repo fixture generates expected artifact fields.

## Phase 4: Observability, Resilience, Security, and Performance
Goal
Harden runtime behavior and add measurable operational signals before release.
Estimate
- 1.5-2.5 dev-days
Owner lane
- Observability/Runtime lane

Tasks
- [x] Emit telemetry events per FDD (`[:priv_signal, :scan, :inventory, :build]`, `[:priv_signal, :scan, :run]`, `[:priv_signal, :scan, :output, :write]`).
- [x] Add structured scan summary logs with cardinality-safe metadata.
- [x] Ensure no PII values are emitted in logs/telemetry; symbols only.
- [x] Add worker timeout handling and dead-task accounting.
- [x] Add concurrency-bound configuration and default caps.
- [x] Add performance smoke benchmark test/script for representative fixture size.
- [x] [Parallel] telemetry verification and perf smoke checks can be implemented in parallel after runner merges.

Tests to write/run
- [x] New `test/priv_signal/scan/telemetry_test.exs`.
- [x] New `test/priv_signal/scan/resilience_test.exs` for parse errors/timeouts.
- [x] New `test/priv_signal/scan/security_redaction_test.exs` ensuring no runtime values leak in logs/artifacts.
- [x] Add benchmark command script or test helper for repeatable timing checks.
- [x] Command: `mix test test/priv_signal/scan/telemetry_test.exs test/priv_signal/scan/resilience_test.exs test/priv_signal/scan/security_redaction_test.exs`

Definition of Done
- Telemetry and log outputs support SLO tracking and troubleshooting.
- Failure modes are contained and do not cause uncontrolled crashes.
- Security redaction expectations are test-verified.

Gate Criteria
- All Phase 4 tests pass.
- Measured runtime on fixture dataset is within accepted target budget envelope.

## Phase 5: Docs, Migration Rollout, and Final Acceptance
Goal
Finalize migration guidance, verify end-to-end acceptance criteria, and prepare safe rollout.
Estimate
- 1.0-1.5 dev-days
Owner lane
- Docs/Release lane

Tasks
- [x] Update `README.md` with `pii` schema, `mix priv_signal.scan` usage, strict mode, and migration instructions from `pii_modules`.
- [x] Update any CLI help/docs for new scanner options and output files.
- [x] Add release notes entry summarizing cutover impact and remediation steps.
- [x] Execute full test suite and targeted scan acceptance scenarios.
- [x] Validate FR checklist against PRD/FDD with explicit pass evidence.
- [x] [Parallel] Documentation updates and release notes can run in parallel with final acceptance execution.

Tests to write/run
- [x] Extend `test/mix/tasks/priv_signal_scan_test.exs` with README example parity cases.
- [x] Run full suite: `mix test`.
- [x] Run format/compile checks: `mix format --check-formatted` and `mix compile --warnings-as-errors`.
- [x] Run acceptance smoke commands:
- [x] `mix priv_signal.validate` with valid `pii` config fixture.
- [x] `mix priv_signal.score` with valid `pii` config fixture.
- [x] `mix priv_signal.scan` with confirmed + possible fixtures.

Definition of Done
- Documentation matches implemented behavior and migration path.
- Full automated suite passes.
- PRD/FDD acceptance criteria are all satisfied with evidence links.

Gate Criteria
- [x] All Phase 5 checks pass with zero unresolved blockers.
- [x] Final FR checklist shows all `SCN-FR-*` marked complete.

## Cross-Phase Risk Register and Owners
- `R-01` Cutover breakage in existing repos using `pii_modules`.
  - Owner: Config lane.
  - Mitigation: explicit schema migration error + README rewrite examples + early contract tests.
- `R-02` Scanner false positives from broad key heuristics.
  - Owner: Scanner core lane.
  - Mitigation: narrow heuristics + `possible_pii` labeling + fixture coverage.
- `R-03` Runtime/perf regressions on large codebases.
  - Owner: Runtime lane.
  - Mitigation: concurrency caps + timeout controls + perf smoke checks.
- `R-04` Nondeterministic ordering under parallel workers.
  - Owner: Scanner core lane.
  - Mitigation: stable fingerprints + deterministic sort test.

## Final Acceptance Checklist
- [x] `SCN-FR-01` through `SCN-FR-09` mapped to passing tests.
- [x] Deprecated `pii_modules` hard-fails with migration instructions.
- [x] `validate` and `score` operate correctly with `pii`-only config.
- [x] `mix priv_signal.scan` emits deterministic JSON + Markdown findings.
- [x] Telemetry events are emitted and cardinality-safe.
- [x] No runtime PII values leak in logs or telemetry.

FR evidence
- `SCN-FR-01`: `test/priv_signal/config_schema_test.exs`, `test/priv_signal/scan_phase0_contract_test.exs`
- `SCN-FR-02`: `test/priv_signal/scan/inventory_test.exs`, `test/priv_signal/scan/determinism_test.exs`
- `SCN-FR-03`: `test/priv_signal/scan/logger_test.exs`
- `SCN-FR-04`: `test/priv_signal/scan/logger_test.exs`, `test/priv_signal/scan/output_json_test.exs`
- `SCN-FR-05`: `test/priv_signal/scan/classifier_test.exs`
- `SCN-FR-06`: `test/priv_signal/scan/output_json_test.exs`, `test/priv_signal/scan/output_markdown_test.exs`, `test/priv_signal/scan_phase0_contract_test.exs`
- `SCN-FR-07`: `test/priv_signal/config_schema_test.exs`, `test/mix/tasks/priv_signal_validate_test.exs`, `test/mix/tasks/priv_signal_score_test.exs`, `test/mix/tasks/priv_signal_scan_test.exs`
- `SCN-FR-08`: `test/priv_signal/validate_test.exs`, `test/mix/tasks/priv_signal_score_test.exs`
- `SCN-FR-09`: `test/mix/tasks/priv_signal_scan_test.exs`, `test/priv_signal/scan/resilience_test.exs`
