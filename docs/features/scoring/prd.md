## 1. Overview

Feature Name

Diff-Based Risk Scoring v2

Summary: Replace `mix priv_signal.score` LLM-first risk detection with a deterministic scoring engine that evaluates semantic lockfile differences between a base ref artifact and the PR workspace artifact. This phase ships Rubric V1, which scores current `mix priv_signal.diff` flow-change events deterministically (flow-proxy path). Optional LLM commentary remains advisory-only and never changes score output.

Links: `docs/features/semantic_diff/prd.md`, `docs/features/scan/prd.md`, `lib/mix/tasks/priv_signal.score.ex`, `lib/mix/tasks/priv_signal.diff.ex`, `lib/priv_signal/diff/semantic.ex`, `lib/priv_signal/diff/severity.ex`

High-Level PR Evaluation Flow (CI/CD)

1. `mix priv_signal.scan` generates/refreshes PR branch lockfile artifact (`priv_signal.lockfile.json`).
2. `mix priv_signal.diff --base origin/main --format json --output tmp/privacy_diff.json` computes semantic changes between base branch lockfile and PR branch lockfile.
3. `mix priv_signal.score --diff tmp/privacy_diff.json --output tmp/priv_signal_score.json` consumes semantic diff JSON and produces deterministic risk label (`NONE|LOW|MEDIUM|HIGH`) with points and machine-readable reasons.
4. Optional advisory step: `mix priv_signal.interpret --diff tmp/privacy_diff.json --score tmp/priv_signal_score.json` (or equivalent future command) generates human-readable summary/commentary only; it must not change deterministic score outputs.
5. CI pulls the final score label and static deterministic explanation from the score JSON artifact for display in the CI UI.  If available, it pulls the LLM analysis of the privacy diff and risk and displays that as well. 

Step Inputs and Outputs (CI/CD Contract)

1. `scan`
- Inputs:
- Repository checkout at PR `HEAD`.
- `priv-signal.yml` configuration.
- Source tree files required by scanners/inference.
- Outputs:
- `priv_signal.lockfile.json` (candidate/PR artifact).
- Optional scan logs/telemetry (`[:priv_signal, :scan, ...]`).

2. `diff`
- Inputs:
- Base ref lockfile artifact (default `origin/main:priv_signal.lockfile.json`).
- Candidate artifact from workspace (`priv_signal.lockfile.json` or `--candidate-path` override).
- CLI options (`--base`, optional `--include-confidence`, `--format`, `--output`).
- Outputs:
- Semantic diff report (human and/or JSON).
- JSON artifact (example `tmp/privacy_diff.json`) containing metadata, summary counts, and normalized changes with severity/rule IDs.
- Exit status non-zero on artifact load/contract/parse failure.

3. `score` (deterministic)
- Inputs:
- Diff JSON artifact produced by `diff` (for example `tmp/privacy_diff.json`).
- Scoring configuration (weights, thresholds, boundary-tier rules, optional strict mode).
- Outputs:
- Deterministic JSON score artifact (example `tmp/priv_signal_score.json`) with:
  - `score`: `NONE|LOW|MEDIUM|HIGH`
  - `points`: integer
  - `summary`: aggregate counters
  - `reasons`: rule-level contributions (`rule_id`, `points`, `change_id`)
- Deterministic human-readable summary for CI logs.
- Telemetry for run/result/rule-hit distribution.

4. `interpret` (optional advisory)
- Inputs:
- Diff artifact (for example `tmp/privacy_diff.json`).
- Score artifact (for example `tmp/priv_signal_score.json`).
- Additional prompt (TBD)
- Advisory model config (`scoring.llm_interpretation.*`) and credentials when enabled.
- Outputs:
- Advisory JSON payload with:
  - `summary`
  - `risk_assessment`
  - `suggested_review_focus`
- Non-fatal advisory error metadata on failure/timeouts.
- No mutation of deterministic `score` artifact fields.

## 2. Background & Problem Statement

Current behavior / limitations.

`mix priv_signal.score` currently validates config, reads raw git diff text, calls an LLM, normalizes/validates LLM output, and computes risk from extracted events. This introduces nondeterminism, requires ongoing prompt/output maintenance, and can drift from code-grounded inferred privacy artifacts. In parallel, the codebase already has deterministic lockfile generation (`mix priv_signal.scan`) and semantic lockfile diffing (`mix priv_signal.diff`), but score is not yet driven by that pipeline.

Who is affected

- Application engineers and reviewers relying on CI score stability.
- Privacy/security reviewers who need auditable, explainable risk deltas.
- Maintainers operating CI workflows and incident triage.

Why now (trigger, dependency, business value)?

- Foundational dependencies now exist: deterministic lockfile generation and semantic diff primitives.
- Moving score to semantic artifact diffs removes core LLM dependency from gating logic.
- Business value: predictable CI behavior, lower operational cost, reduced false confidence from speculative interpretation.

## 3. Goals & Non-Goals

Goals: Bullet list of outcomes; measurable where possible.

- Deliver deterministic risk scoring based solely on semantic diff JSON output (`version: v1`, `changes: [...]`) from `mix priv_signal.diff`.
- Ensure identical base/candidate artifacts always produce identical score and JSON output ordering.
- Produce one canonical score label: `NONE | LOW | MEDIUM | HIGH`.
- Emit explainable score rationale with per-change contribution metadata.
- Preserve optional advisory LLM interpretation behind explicit config, disabled by default.
- Keep CLI execution functional without any LLM credentials.
- Remove legacy `flows` config dependency and all flow-based risk logic from score execution.

Non-Goals: Explicitly out of scope to prevent scope creep.

- Rebuilding scanner/inference architecture in this phase.
- Real-time UI/dashboard beyond CLI output and telemetry.
- Policy-as-code workflow enforcement beyond current score command contract.
- Automatic CI exit-code enforcement changes (tracked as follow-on, optional phase).

## 4. Users & Use Cases

Primary Users / Roles

- Developer (runs locally and in PR CI).
- Reviewer (consumes JSON/human output in code review).
- Privacy/Security engineer (audits risk rationale and rule behavior).
- Platform maintainer (operates config defaults and telemetry alerts).

Use Cases / Scenarios: Short narratives (1–3 paragraphs) or bullets.

- A developer updates code causing a new external sink node and new node-to-node transfer. Running `mix priv_signal.scan`, `mix priv_signal.diff --base origin/main --format json --output tmp/privacy_diff.json`, and `mix priv_signal.score --diff tmp/privacy_diff.json --output tmp/priv_signal_score.json` returns `HIGH` with deterministic evidence.
- A PR only refactors internals with no semantic lockfile changes; score returns `NONE` across repeated runs.
- A reviewer sees `MEDIUM` caused by multiple additive moderate node events (for example PII category expansion plus internal node transfer addition) and focuses review on listed reasons.
- A team enables optional LLM interpretation for human summary text; the deterministic score remains unchanged with the flag on/off.

## 5. UX / UI Requirements

Key Screens/States: List and short description per screen/state.

- CLI success with non-empty diff: score label, points, summary counters, and deterministic reasons.
- CLI success with empty diff: `NONE`, zero points, empty/zeroed summaries.
- CLI failure states: actionable errors for missing base artifact, missing candidate artifact, contract mismatch, invalid config.
- Optional advisory section: included only when enabled and LLM call succeeds; otherwise omitted or populated with explicit advisory error metadata.

Navigation & Entry Points: Where in the system this lives (menus, context actions).

- Primary entrypoint: `mix priv_signal.score`.
- Supporting prerequisites: `mix priv_signal.scan` and base ref lockfile presence.
- Optional debugging/triage: `mix priv_signal.diff`.

Accessibility: WCAG 2.1 AA; keyboard-only flows; screen-reader expectations; alt-text and focus order; color contrast.

- CLI-only feature; output must be plain-text and JSON machine-readable, no color-only meaning.
- Human-readable output must not rely solely on ANSI color for severity differentiation.
- Structured JSON fields must allow downstream accessible renderers in CI tooling.

Internationalization: Text externalized, RTL readiness, date/number formats.

- CLI messages remain English-only in this phase.
- Numeric fields (points/counts) emitted as numbers in JSON to avoid locale parsing issues.
- Human text is deterministic and template-driven to enable future extraction.

Screenshots/Mocks: Reference pasted images (e.g., ![caption](image-1.png)).

- No screenshots provided.

## 6. Functional Requirements

Provide an ID’d list (FR-001, FR-002, …). Each must be testable.

| ID | Description | Priority (P0/P1/P2) | Owner |
|---|---|---|---|
| FR-001 | `mix priv_signal.score` shall accept a semantic diff JSON artifact as input and compute deterministic risk from that artifact (not from git patch text or direct git ref resolution). | P0 | Engineering |
| FR-002 | Scoring engine shall be pure/deterministic: no LLM/network call in deterministic scoring path. | P0 | Engineering |
| FR-003 | Score labels shall be restricted to `NONE`, `LOW`, `MEDIUM`, `HIGH`. | P0 | Engineering |
| FR-004 | `NONE` shall be returned only when semantic diff contains zero scoring-relevant changes. | P0 | Engineering |
| FR-005 | Engine shall score by additive weighted points (default rubric), with configurable weights and thresholds in config. | P0 | Engineering |
| FR-006 | Engine shall include boundary-tier overlay logic that can escalate bucket based on trust-boundary movement. | P0 | Engineering |
| FR-007 | Engine shall treat optional LLM interpretation as advisory-only and non-influential to deterministic score/points/bucket. | P0 | Engineering |
| FR-008 | Output JSON shall include `score`, `points`, `summary`, and deterministic `reasons` array with rule identifiers. | P0 | Engineering |
| FR-009 | Summary shall include at minimum: total node changes, external node additions, high-sensitivity-related changes, transform removals, and new vendor/domain additions (when detectable). | P0 | Engineering |
| FR-010 | Diff classification for scoring in this phase shall support flow-proxy semantic change entries from diff JSON `version: v1` with required fields `type`, `flow_id`, `change`, and optional `details`. | P0 | Engineering |
| FR-011 | Each scored diff item shall carry normalized fields when available: `type`, `flow_id`, `change`, `rule_id`, `severity`, and `details`. | P0 | Engineering |
| FR-012 | If required diff artifact fields are unavailable in artifact input, score shall fail with explicit contract error and no LLM/flow-validation fallback execution. | P0 | Engineering |
| FR-013 | Config schema shall support `scoring.llm_interpretation.enabled` (default `false`) and model selection key for advisory calls. | P1 | Engineering |
| FR-014 | Config schema shall support score weight/threshold overrides with safe validation and defaults. | P1 | Engineering |
| FR-015 | CLI shall remain operational without LLM credentials when advisory interpretation is disabled. | P0 | Engineering |
| FR-016 | Score pipeline shall emit telemetry for run start/stop/error, score distribution, rule hit counts, and advisory invocation outcomes. | P0 | Engineering |
| FR-017 | Legacy flow configuration and flow-based risk modules (including `PrivSignal.Risk.Assessor` score path usage) shall be fully removed from score v2 codepaths and config contracts. | P0 | Engineering |
| FR-018 | Determinism tests shall prove stable outputs for repeated runs on identical input artifacts and independent key-order variations. | P0 | Engineering |
| FR-019 | Documentation in `docs/features/scoring/{prd,fdd,plan}.md` and command help text shall reflect new scoring contract. | P0 | Engineering |
| FR-020 | Optional future exit-code policy (`HIGH` non-zero, `MEDIUM` warning) shall be feature-flagged or deferred; default behavior unchanged in this phase. | P2 | Engineering |
| FR-021 | CI/CD orchestration shall define explicit execution order: `diff` completes before deterministic `score`; optional advisory `interpret` runs only after score output is available. | P0 | Engineering |

## 7. Acceptance Criteria (Testable)

Use Given / When / Then. Tie each criterion to one or more FR IDs.

AC-001 (FR-001, FR-002, FR-018)
Given base and candidate lockfiles with identical semantic content  
When `mix priv_signal.diff --base origin/main --format json --output tmp/privacy_diff.json` is followed by repeated runs of `mix priv_signal.score --diff tmp/privacy_diff.json --output tmp/priv_signal_score.json`  
Then output `score`, `points`, `summary`, and `reasons` are byte-for-byte stable.

AC-002 (FR-003, FR-004)
Given no semantic diff changes  
When score runs  
Then `score = "NONE"` and `points = 0`.

AC-003 (FR-005, FR-008)
Given one internal `flow_added` event with default weights  
When score runs  
Then points increase by configured internal-transfer weight and bucket maps to expected label.

AC-004 (FR-005, FR-006)
Given diff includes a new external HTTP sink and high-sensitivity PII expansion  
When score runs  
Then total points and final bucket are `HIGH`, and reasons include both contributing rule IDs.

AC-005 (FR-007, FR-013, FR-015)
Given advisory interpretation flag is disabled  
When score runs without model credentials  
Then scoring succeeds and output sets `llm_interpretation` to `null`.

AC-006 (FR-007, FR-013)
Given advisory interpretation flag is enabled and model call fails  
When score runs  
Then deterministic score fields are still returned unchanged and advisory failure is reported as non-fatal metadata.

AC-007 (FR-010, FR-011, FR-012)
Given a diff artifact missing required `version`/`changes` shape or required per-change fields  
When score runs  
Then score exits non-zero with explicit contract validation error and no flow-based fallback execution.

AC-008 (FR-014)
Given custom weight/threshold overrides in config  
When score runs on the same diff  
Then points/bucket reflect overrides and config validation rejects invalid override values.

AC-009 (FR-016)
Given successful score run  
When telemetry is captured  
Then events include run duration, total points, final bucket, and per-rule hit counts.

AC-010 (FR-017, FR-019)
Given score v2 is enabled as default path  
When running `mix priv_signal.score --help` and docs review  
Then help/docs describe lockfile diff-based scoring and no longer describe LLM as required for risk detection.

AC-011 (FR-021, FR-007)
Given CI pipeline for PR evaluation  
When the privacy risk stage executes  
Then `mix priv_signal.diff` runs before `mix priv_signal.score`, and any optional advisory `interpret` step runs after score and does not modify `score`, `points`, `summary`, or `reasons`.

## 8. Non-Functional Requirements

Performance & Scale: targets for latency (p50/p95), throughput, and expected concurrency; LiveView responsiveness; pagination/streaming if needed.

- CLI runtime target for deterministic scoring path only:
- p50 <= 1.5s and p95 <= 5s for artifacts up to 10k nodes on CI-class runners.
- Advisory LLM path measured separately and excluded from deterministic performance SLO.
- Memory target <= 300MB peak for 10k-node artifacts.
- No LiveView/UI responsiveness scope in this feature.

Reliability: error budgets, retry/timeout behavior, graceful degradation.

- Deterministic scoring path availability target: 99.9% in CI runs (excluding git/artifact absence).
- Advisory LLM call timeout default <= 8s and max one retry with exponential backoff; failures are non-fatal.
- Contract/parse failures return actionable errors and non-zero exit.

Security & Privacy: authentication & authorization, PII handling, FERPA-adjacent considerations, rate limiting/abuse protection.

- No runtime student/user PII values shall be emitted; only declared field/category metadata from lockfile artifacts.
- Advisory prompt payload must redact code literals beyond required structural summary.
- If advisory is enabled, enforce rate-limited model invocation (single request per score run).

Compliance: accessibility (WCAG), data retention, audit logging.

- CLI output remains plain and parseable for accessible downstream tools.
- Score outputs retained per existing CI artifact retention policy; no new long-term storage introduced.
- Auditability via deterministic reasons + telemetry rule IDs.

Observability: telemetry events, metrics, logs, traces; AppSignal dashboards & alerts to add/modify.

- Add/modify telemetry:
- `[:priv_signal, :score, :run, :start|:stop|:error]`
- `[:priv_signal, :score, :rule_hit]`
- `[:priv_signal, :score, :advisory, :start|:stop|:error]`
- AppSignal dashboards:
- Score bucket trend over time.
- Rule hit count top-N.
- Run failures by reason.
- Alerts:
- Error rate > 2% over 15m.
- Sudden `HIGH` spike > 3x 7-day baseline.

## 9. Data Model & APIs

Ecto Schemas & Migrations: new/changed tables, columns, indexes, constraints; sample migration sketch.

- No Ecto/Postgres schema changes in this phase (CLI file-based workflow).
- No DB migrations required.

Context Boundaries: which contexts/modules change (e.g., Oli.Delivery.Sections, Oli.Resources, Oli.Publishing, Oli.GenAI).

- `Mix.Tasks.PrivSignal.Score` to orchestrate lockfile-based pipeline.
- New module family (proposed): `PrivSignal.Score.*` for options, engine, rubric, summary, output.
- Reuse/extend `PrivSignal.Diff.*` for semantic diff input and normalization.
- Remove `PrivSignal.Risk.Assessor` from score command path and delete legacy flow-based score logic.
- Optional advisory module: `PrivSignal.Score.Advisory` wrapping existing LLM client.

APIs / Contracts: new/updated functions, JSON shapes, LiveView events/assigns, REST/GraphQL (if any).

- Proposed core API:
- `PrivSignal.Score.Engine.score(diff_report, opts) :: {:ok, score_report} | {:error, reason}`
- `PrivSignal.Score.Rubric.apply(changes, rubric_config) :: %{points: non_neg_integer(), reasons: list(), summary: map()}`
- `PrivSignal.Score.Advisory.interpret(score_report, opts) :: {:ok, map()} | {:error, reason}`
- CLI JSON contract (v1 deterministic score artifact):
```json
{
  "version": "v1",
  "score": "MEDIUM",
  "points": 6,
  "summary": {
    "nodes_added": 1,
    "external_nodes_added": 1,
    "high_sensitivity_changes": 0,
    "transforms_removed": 0,
    "new_external_domains": 0,
    "ignored_changes": 0,
    "relevant_changes": 2,
    "total_changes": 2
  },
  "reasons": [
    { "rule_id": "R-HIGH-EXTERNAL-SINK-ADDED", "points": 6, "change_id": "flow:payments:external_sink_added" }
  ],
  "llm_interpretation": {
    "summary": "Optional advisory",
    "risk_assessment": "Optional advisory",
    "suggested_review_focus": ["Optional advisory"]
  }
}
```

Permissions Matrix: role × action table.

| Role | Run `scan` | Run `diff` | Run `score` | Enable advisory LLM | Modify scoring weights |
|---|---|---|---|---|---|
| Developer | Yes | Yes | Yes | Project policy dependent | No (default) |
| CI Bot | Yes | Yes | Yes | No (default) | No |
| Privacy Engineer | Yes | Yes | Yes | Yes | Yes |
| Repository Admin | Yes | Yes | Yes | Yes | Yes |

## 10. Integrations & Platform Considerations

- Advisory-only optional integration via existing `PrivSignal.LLM.Client`.
- Default disabled (`scoring.llm_interpretation.enabled: false`).
- Advisory input is structured diff summary and top weighted changes only.
- No fallback model required for deterministic path correctness.

- No cache requirement for v2; all computation is in-memory per run.
- Deterministic ordering applied before scoring/output to prevent nondeterministic maps/lists.


## 11. Feature Flagging, Rollout & Migration

N/A.  No feature flag.

## 12. Analytics & Success Metrics

North Star / KPIs: define how success is measured.

- Deterministic consistency KPI: 100% identical outputs for identical inputs in CI replay tests.
- Reliability KPI: score command failure rate < 2% excluding missing artifact/setup errors.
- Explainability KPI: >= 95% of sampled `HIGH/MEDIUM` scores have reviewer-accepted rationale.

Event Spec: name, properties, user/section/project identifiers, PII policy.

- `score_run_completed`
- Properties: `engine_mode`, `score`, `points`, `duration_ms`, `changes_total`, `rules_hit`, `include_advisory`.
- IDs: repository slug/hash, base ref, candidate ref/sha.
- PII policy: never include runtime payload values or source code excerpts in telemetry properties.

## 13. Risks & Mitigations

- Risk: rubric weights over/underfit real risk.
- Mitigation: configuration overrides + calibration suite with golden fixtures and periodic review.

- Risk: current lockfile schema may not expose all required node-level fields for scoring dimensions.
- Mitigation: enforce strict score input contract for node fields; fail closed with explicit error and schema upgrade guidance.

- Risk: rollout changes score distribution and causes CI churn.
- Mitigation: staged rollout with golden fixture baselines and deterministic rule calibration; no legacy flow path fallback.

- Risk: advisory LLM perceived as authoritative despite non-deterministic nature.
- Mitigation: explicit output labeling as advisory-only and strict separation from deterministic fields.

## 14. Open Questions & Assumptions

Assumptions (made by this PRD)

- Current canonical lockfile path is `priv_signal.lockfile.json`; user-provided `privsignal.json` is treated as notional.
- Existing semantic diff modules are reused rather than rebuilt.
- No database persistence is required for scoring v2.
- Default scoring rubric is weighted points plus boundary-tier escalation overlay.
- Legacy `flows` configuration and flow-based score logic are removed and are out of scope for all new scoring behavior.

Open Questions (needs resolution)

- Which exact node/edge schema version and required fields become the minimum contract for score input (`v1` vs new version)?
- What exact default weight and threshold values should ship for first production calibration?
- Should exit code semantics (`HIGH` non-zero) be included now behind a flag, or deferred entirely?
- What is the maximum advisory payload allowed for cost control when enabled?

## 15. Timeline & Milestones (Draft)


## 16. QA Plan

Automated: unit/property tests, LiveView tests, integration tests, migration tests.

- Unit tests for each scoring rule and bucket mapping.
- Property tests for determinism and ordering invariance.
- Integration tests for `mix priv_signal.score` with fixture lockfiles across scenarios (`NONE/LOW/MEDIUM/HIGH`).
- Config validation tests for scoring override keys and advisory flags.
- No LiveView tests or DB migration tests required.

Manual: key exploratory passes, regression areas, accessibility checks.

- Run score locally across representative PR fixture set; verify rationale readability.
- Regression pass for existing `scan` and `diff` commands.
- Verify CLI output remains readable without color and JSON remains schema-stable.

## 17. Definition of Done

- [ ] Docs updated
- [ ] Legacy flow-based scoring codepaths removed from score runtime
- [ ] Telemetry & alerts live
- [ ] Migrations & rollback tested
- [ ] Accessibility checks passed
- [ ] `mix priv_signal.score` computes deterministic score from lockfile semantic diff
- [ ] Advisory LLM path is optional, default-off, and non-blocking
