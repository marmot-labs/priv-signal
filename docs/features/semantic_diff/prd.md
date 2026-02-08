## 1. Overview

Feature Name
Artifact Diff Engine (Semantic Privacy Diff)

Summary: The Artifact Diff Engine compares committed privacy lockfile artifacts and reports privacy-meaningful changes instead of raw file diffs. It loads the base lockfile from a git ref and, by default, loads the candidate lockfile from the checked-out workspace (with optional candidate-ref override). It classifies added/removed/changed flows, assigns deterministic severity, and produces both human-readable and JSON output for PR review and CI automation.

Spec Alignment Note (2026-02-08): PRD and FDD are aligned on hybrid input mode (`--base` ref + workspace candidate default, optional `--candidate-ref`). `diff` remains analysis-only and never runs `infer`.

Workflow Fit in PrivSignal:
PrivSignal operates using a clear separation between authoritative configuration, generated baseline artifacts, and analysis-only comparison tools. This separation ensures that privacy behavior cannot change implicitly and that all changes are deliberate, reviewable, and enforced by CI.

1. Authoritative configuration (manual)

A developer begins by authoring or updating the repository-root configuration file (priv-signal.yml). This file defines the project’s privacy intent, including:

which Elixir modules contain PII,

which fields within those modules are considered PII, and

optional metadata such as category and sensitivity.

This file is always human-authored and version-controlled.

2. Baseline inference and lockfile update (manual, explicit)

After making code changes or updating priv-signal.yml, the developer runs:

mix priv_signal.infer --write-lock


This command performs a full, AST-driven static analysis of the current codebase and generates a proto–data-flow lockfile that captures the inferred, privacy-relevant behavior of the system (e.g., PII usage at logs, boundaries, and sinks). The resulting lockfile is treated as a generated artifact, committed to the repository, and represents the accepted privacy baseline for that code state.

Updating the lockfile is an explicit action and signals that the developer acknowledges and accepts the inferred privacy behavior.

3. Continuous integration enforcement (automatic)

In CI, PrivSignal enforces the freshness of the lockfile by running:

mix priv_signal.infer --check-lock


This command re-runs inference in memory and verifies that the committed lockfile exactly matches the inferred privacy behavior of the code under test. If the lockfile is missing or out of date, CI fails with a clear message instructing the developer to regenerate and commit the lockfile. CI never updates artifacts itself.

4. Semantic privacy diff for PR review (analysis-only)

For pull request review, PrivSignal provides a separate command:

mix priv_signal.diff --base <ref> [--candidate-ref <ref>]


The diff command does not run inference and does not modify any artifacts. It loads the committed proto-data-flow lockfile at the base reference (e.g., target branch), then compares it against the candidate lockfile from the current workspace by default (or from `--candidate-ref` when provided). It then produces a semantic privacy diff that explains how privacy-relevant behavior has changed, such as:

added or removed data flows,

changes in sinks or trust boundaries,

expansion of PII usage, or

changes in severity.

This diff is presented in both human-readable form (for reviewers) and structured JSON (for CI annotations), allowing reviewers to understand what changed in privacy terms, rather than inspecting raw file diffs.

5. Review and merge

Reviewers evaluate the semantic privacy diff alongside the code changes. If the privacy impact is acceptable and the lockfile is up to date, the PR can be merged. The updated lockfile merges with the PR, ensuring the main branch’s privacy baseline remains current without requiring any follow-up changes.

Links: `docs/features/semantic_diff/informal.md`, `docs/prd.md`, `docs/fdd.md`, Epic: Semantic Diff Phase 3 (to be linked in tracker)

## 2. Background & Problem Statement

Current behavior / limitations.
PrivSignal already generates structured privacy artifacts (PII declarations, scanner outputs), but reviewers currently rely on line-level diffs or raw JSON deltas. These are noisy (ordering/format/metadata churn), do not encode privacy semantics, and force manual risk inference.

Who is affected
- PR reviewers (engineering, security, privacy)
- Developers authoring data-flow and PII updates
- CI operators consuming machine outputs

Why now (trigger, dependency, business value)?
Phase 3 depends on prior artifact generation maturity and is needed to make CI feedback actionable. Clear semantic diffs reduce review time, improve risk detection quality, and increase trust in privacy automation.

## 3. Goals & Non-Goals

Goals:
- Deliver `mix priv_signal.diff --base <ref>` with hybrid input mode (workspace candidate by default, optional `--candidate-ref`) to compare artifact snapshots.
- Detect semantic privacy changes for flows and PII (added/removed/changed) while ignoring formatting/order noise.
- Assign deterministic severity (`high`/`medium`/`low`) per change using v1 rules.
- Emit a human-readable summary optimized for PR comments and a structured JSON payload for automation.
- Keep runtime suitable for CI usage on typical PRs (see NFR targets).

Non-Goals:
- Blocking merges or enforcing policy outcomes based on severity.
- Probabilistic or ML-based risk scoring.
- Full reconstruction of system-wide end-to-end flow graphs.
- Arbitrary diffing of all config files outside privacy artifacts.

## 4. Users & Use Cases

Primary Users / Roles
- Developer (author): wants immediate explanation of privacy impact before requesting review.
- PR reviewer (security/privacy/tech lead): wants high-signal summary of changed risk.
- CI integrator/platform engineer: wants stable JSON contract for checks and dashboards.

Use Cases / Scenarios:
- A developer adds a new export flow to an external sink. CI comment should clearly say an external disclosure was added, list impacted fields, and label severity high.
- A reviewer sees a modified flow where only metadata/order changed. Diff should report no semantic changes.
- A team adds new PII fields to an existing internal flow. Output should highlight expansion and sensitivity impact with medium severity.
- A scanner confidence level changes from possible to confirmed with no flow change. Output should surface low-severity confidence change when enabled.

## 5. UX / UI Requirements

Key Screens/States: List and short description per screen/state.
- CLI success (human default): grouped sections by severity with concise bullets and relevant details.
- CLI success (JSON mode): machine-readable object with summary counts and normalized change records.
- CLI no-change state: explicit message indicating no privacy-relevant semantic changes.
- CLI error state: actionable errors for invalid refs, missing artifacts, parse failures, and unsupported schema versions.

Navigation & Entry Points: Where in the system this lives (menus, context actions).
- Entry point: Mix task `mix priv_signal.diff --base <ref> [--candidate-ref <ref>] [--candidate-path <path>] [--format human|json] [--include-confidence]`.
- Typical invocation from local dev and CI steps.

Accessibility: WCAG 2.1 AA; keyboard-only flows; screen-reader expectations; alt-text and focus order; color contrast.
- CLI output must not rely on color alone to communicate severity; include textual severity labels.
- Output must be readable in plain-text contexts and compatible with screen-reader parsing of headings/lists.
- JSON output must preserve explicit fields for severity/type/details for assistive tooling.


## 6. Functional Requirements

| ID | Description | Priority (P0/P1/P2) | Owner |
|---|---|---|---|
| FR-001 | Provide `mix priv_signal.diff --base <ref>` command that resolves base lockfile from git ref and candidate lockfile from workspace by default, with optional `--candidate-ref`. | P0 | Engineering |
| FR-002 | Normalize parsed artifacts before diffing to ignore ordering, formatting, and irrelevant metadata changes. | P0 | Engineering |
| FR-003 | Detect semantic category `flow_added` and `flow_removed` with flow identifiers and core attributes. | P0 | Engineering |
| FR-004 | Detect `flow_changed` subtypes: `external_sink_added_removed`, `pii_fields_expanded_reduced`, `boundary_changed`. | P0 | Engineering |
| FR-005 | Assign deterministic severity per v1 rule set and include rule identifier in each change record. | P0 | Engineering |
| FR-006 | Emit human-readable summary grouped by severity with concise, reviewer-friendly details. | P0 | Engineering |
| FR-007 | Emit JSON output with stable schema: summary counts + normalized changes array + metadata. | P0 | Engineering |
| FR-008 | Support optional confidence-level diffing (possible/confirmed transitions) behind flag/config with low default priority. | P1 | Engineering |
| FR-009 | Return deterministic exit codes (`0` success including no-change; non-zero on command/runtime/parsing errors). | P0 | Engineering |
| FR-010 | Include artifact provenance metadata (base ref, candidate source descriptor, artifact versions, timestamp) in output. | P1 | Engineering |
| FR-011 | Provide telemetry events and metrics for diff runs, change counts, severities, and failures. | P0 | Engineering |
| FR-012 | Ensure behavior is backward-compatible with current artifact schema versions used by prior phases. | P0 | Engineering |
| FR-013 | Perform semantic comparison strictly between base and candidate committed lockfile artifacts; `diff` must not execute inference. | P0 | Engineering |

## 7. Acceptance Criteria (Testable)

AC-001 (FR-001)
Given a valid `--base` ref and a valid candidate workspace lockfile
When `mix priv_signal.diff` runs
Then the command loads base artifact from git ref and candidate artifact from workspace, then completes semantic comparison without running infer.

AC-002 (FR-001, FR-009)
Given an invalid base git ref or missing candidate workspace artifact
When the command runs
Then it exits non-zero and prints actionable error guidance naming the failing ref/artifact.

AC-003 (FR-002)
Given two artifacts that differ only by key order, whitespace, or non-semantic metadata
When diffing
Then output reports no semantic changes.

AC-004 (FR-003)
Given candidate introduces a new flow absent in the lockfile baseline
When diffing
Then output contains one `flow_added` change with flow id, sinks, and PII field summary.

AC-005 (FR-003)
Given candidate removes a flow present in the lockfile baseline
When diffing
Then output contains one `flow_removed` change with low severity.

AC-006 (FR-004)
Given a flow in candidate adds an external sink compared to base
When diffing
Then output classifies `flow_changed` + `external_sink_added` and severity `high`.

AC-007 (FR-004)
Given a flow adds high-sensitivity PII fields
When diffing
Then output classifies `pii_fields_expanded` and severity follows rules (`high` if logging high sensitivity, else `medium`).

AC-008 (FR-004)
Given a flow changes from internal-only to crossing system boundary
When diffing
Then output includes `boundary_changed` with severity `high`.

AC-009 (FR-005)
Given identical semantic changes across repeated runs
When command executes multiple times
Then assigned severity and rule identifiers are identical.

AC-010 (FR-006)
Given at least one high, medium, and low change
When human output is generated
Then sections appear grouped by severity and can be read in under 30 seconds by including only high-signal fields.

AC-011 (FR-007)
Given `--format json`
When command runs
Then output matches documented JSON schema including `summary` counts and `changes[]` objects with `type`, `flow_id`, `change`, `severity`, and `details`.

AC-012 (FR-008)
Given confidence diffing is disabled
When confidence-only changes exist
Then they are omitted from output.

AC-013 (FR-008)
Given confidence diffing is enabled
When `possible -> confirmed` occurs
Then output includes a low-severity `confidence_changed` record.

AC-014 (FR-010)
Given successful diff execution
When output is emitted
Then it includes base ref, candidate source descriptor (workspace path or candidate ref), and artifact schema versions.

AC-015 (FR-011)
Given a successful and a failed run
When telemetry is inspected
Then `diff_run_started`, `diff_run_completed`, and `diff_run_failed` events are present with expected properties.

AC-016 (FR-013)
Given a candidate branch modifies YAML configuration but lockfile is unchanged
When `mix priv_signal.diff` runs
Then the command reports no semantic differences because it compares committed lockfiles only and does not infer from YAML at diff time.

AC-017 (FR-013)
Given the candidate workspace lockfile artifact is missing
When `mix priv_signal.diff` runs
Then the command exits non-zero with an actionable error instructing the developer to run `mix priv_signal.infer --write-lock` and commit the updated lockfile.

AC-018 (FR-001, FR-013)
Given valid `--base` and `--candidate-ref` values
When `mix priv_signal.diff` runs
Then the command loads both artifacts from git refs, performs semantic comparison, and does not execute inference.

## 8. Non-Functional Requirements

Performance & Scale:
- p50 runtime <= 1.0s and p95 runtime <= 3.0s for up to 500 flows and 5,000 PII field references per snapshot on CI runner baseline.
- Memory footprint <= 250 MB at p95 for target dataset.
- Deterministic runtime characteristics; no network dependency in core diff path.

Reliability:
- Command success rate >= 99.5% excluding invalid user input.
- Explicit timeout of 30s for artifact extraction/parsing per ref.
- Graceful degradation: if optional scanner artifact missing, proceed with warning unless strict mode enabled.

Security & Privacy:
- Respect least-privilege access to repository contents only.
- Never emit raw sensitive values beyond declared field identifiers/categories.
- Sanitize logs/errors to avoid leaking secrets from environment or scanner raw payloads.
- Optional rate limiting for repeated CI invocations to avoid abuse (pipeline-level control).

Compliance:
- WCAG text-only readability constraints for CLI output.
- Auditability via persisted CI logs and optional JSON artifact retention policy.

Observability:
- AppSignal metrics: runtime histogram, failure count, semantic change counts by severity and type.
- Structured logs with correlation id per run.
- Telemetry events: `diff_run_started`, `diff_run_completed`, `diff_run_failed`, `diff_artifact_loaded`, `diff_compared`.
- Alerts: failure rate > 5% over 1h; p95 runtime > 3.0s sustained over 30m.

## 9. Data Model & APIs

Ecto Schemas & Migrations: new/changed tables, columns, indexes, constraints; sample migration sketch.
- No database schema changes required for v1 CLI-only operation.
- Optional future persistence (not in scope): `privacy_diff_runs` and `privacy_diff_changes` tables for analytics.

Context Boundaries: which contexts/modules change (e.g., Oli.Delivery.Sections, Oli.Resources, Oli.Publishing, Oli.GenAI).
- `PrivSignal.Mix.Tasks.Diff` (new): command entrypoint and argument parsing.
- `PrivSignal.Artifacts.Loader` (update/new): load artifacts per git ref.
- `PrivSignal.Diff.Normalize` (new): canonicalization of parsed artifacts.
- `PrivSignal.Diff.Semantic` (new): semantic comparators and change classification.
- `PrivSignal.Diff.Severity` (new): deterministic rule engine.
- `PrivSignal.Diff.Renderer.Human` and `PrivSignal.Diff.Renderer.JSON` (new): output formatters.
- `PrivSignal.Telemetry` (update): diff-related events/metrics.

APIs / Contracts: new/updated functions, JSON shapes, LiveView events/assigns, REST/GraphQL (if any).
- CLI:
  - `mix priv_signal.diff --base <ref> [--candidate-ref <ref>] [--candidate-path <path>] [--format human|json] [--include-confidence] [--output <path>]`
- Internal API sketch:
  - `PrivSignal.Diff.run(base_ref, candidate_source, opts) :: {:ok, DiffReport.t()} | {:error, DiffError.t()}`
  - `PrivSignal.Diff.normalize(artifacts) :: NormalizedArtifacts.t()`
  - `PrivSignal.Diff.compare(base, candidate, opts) :: [SemanticChange.t()]`
- JSON schema (v1):
  - `version`: string
  - `metadata`: `%{base_ref, candidate_source, generated_at, artifact_versions}`
  - `summary`: `%{high, medium, low, total}`
  - `changes`: list of `%{id, type, flow_id, change, severity, rule_id, details}`

Permissions Matrix: role × action table.

| Role | Run diff command | View human output | Consume JSON output | Configure confidence diff |
|---|---|---|---|---|
| Repo contributor | Yes (local/CI) | Yes | Yes | Yes (repo config) |
| PR reviewer | Yes | Yes | Yes | No (unless maintainer) |
| Repo maintainer | Yes | Yes | Yes | Yes |
| External/LTI learner role | No | No | No | No |

## 10. Integrations & Platform Considerations
- N/A
## 11. Feature Flagging, Rollout & Migration
- NONE needed

## 12. Analytics & Success Metrics

North Star / KPIs: define how success is measured.
- Reviewer clarity KPI: >= 80% of surveyed reviewers report output is sufficient without opening raw artifacts.
- Operational KPI: >= 50% reduction in PR comments asking “what changed?” for privacy artifacts within 8 weeks.
- Quality KPI: <= 5% of reported semantic diffs classified as misleading/incorrect in sampled audits.

## 13. Risks & Mitigations

- Technical risk: false positives from imperfect normalization.
  - Mitigation: golden corpus tests for no-op formatting/order changes; deterministic canonicalization contract tests.
- Product risk: severity perceived as policy enforcement.
  - Mitigation: explicit advisory wording in output and docs.
- Operational risk: CI runtime regression on large repos.
  - Mitigation: performance budgets, benchmark gate in CI, optimize parser/cache path.
- Compatibility risk: artifact schema drift across versions.
  - Mitigation: schema version checks, adapters for supported versions, clear error messaging for unsupported versions.
- Legal/privacy risk: sensitive data leak in logs.
  - Mitigation: structured redaction policy and logging tests.

## 14. Open Questions & Assumptions

Assumptions (made by this PRD)
- Artifact snapshots can be deterministically loaded from base ref and candidate workspace (or candidate ref when provided) using existing project mechanisms.
- Severity rules are static and maintained in config/code, not user-editable at runtime in v1.
- Confidence diffs are optional and disabled by default.
- CLI is primary UX surface; no LiveView/UI work is required in this phase.

Open Questions
- Should missing optional scanner artifacts be warning-only or configurable as hard-fail in CI strict mode?
- What is the canonical list of “high-sensitivity” field categories for severity mapping?
- Should JSON schema be versioned as semantic version (`1.0.0`) or major-only (`v1`)?
- Is repo-level flag sufficient, or is pipeline/job-level override required as first-class config?
- What baseline dataset should be used to certify p95 performance targets before full rollout?

## 15. QA Plan

Automated: unit/property tests, LiveView tests, integration tests, migration tests.
- Unit tests for each comparator and severity rule.
- Property tests for normalization invariants (ordering/format insensitivity).
- Integration tests for CLI across refs and output modes.
- Schema contract tests for JSON output compatibility.

Load/Perf: how we’ll verify NFRs.
- NONE 

## 16. Definition of Done

- [ ] `prd.md` approved and aligned with implementation scope.
- [ ] `mix priv_signal.diff` implemented with human and JSON outputs.
- [ ] Semantic categories and severity rules covered by automated tests.
- [ ] Noise suppression (ordering/format/metadata) verified by golden tests.
