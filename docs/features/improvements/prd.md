## 1. Overview

Feature Name

PrivSignal Scanner Recall & Explainability Improvements (Normalization, Wrapper Detection, HTTP Provenance, Confidence Tiers)

Summary: Improve scanner recall for realistic code patterns while preserving deterministic behavior and explainability. The feature adds controlled fuzzy PRD matching, wrapper-aware database sink detection, HTTP payload provenance tracking, and a staged confidence model so PrivSignal catches more real privacy drift without turning noisy.

Links: Issues, epics, design files, related docs

- Related notes: `docs/features/improvements/staged_branch_observations.md`
- Classification registry: `docs/classification_registry.md`
- Existing scanner docs: `docs/features/scan/fdd.md`

## 2. Background & Problem Statement

Current behavior / limitations in Torus.

PrivSignal currently misses realistic patterns observed in staged Torus validation branches:

- PRD token matching is mostly literal (for example `email`, `user_id`) and misses derived tokens like `invitee_emails`.
- Database detection is callsite-driven on explicit `Repo.*` usage and misses wrapper indirection (for example `Persistence.append_step(...)`).
- HTTP detection requires payload evidence visible in sink call arguments; prebuilt/encoded payloads can hide PRD lineage.

Who is affected (Authors, Instructors, Students, Admins)?

- PrivSignal maintainers and platform engineers operating CI privacy checks.
- Product/security/privacy reviewers relying on scan/diff/score outputs.
- Torus delivery teams (authoring and delivery contexts) whose PRs are scored.

Why now (trigger, dependency, business value)?

Trigger is empirical validation in 10 staged Torus branches that exposed recall gaps. Fixing these limitations now improves confidence in PrivSignal rollout quality and reduces false negatives before broader adoption.

## 3. Goals & Non-Goals

Goals: Bullet list of outcomes; measurable where possible.

- Increase scanner recall for realistic naming/indirection patterns while keeping deterministic output.
- Add explicit, reviewable matching controls via config (aliases/synonyms, wrapper definitions).
- Preserve explainability by emitting evidence chains and confidence tiers.
- Keep false-positive growth bounded with strict/controlled matching modes.
- Provide fixture-based regression coverage for each observed limitation.

Non-Goals: Explicitly out of scope to prevent scope creep.

- Whole-program inter-module call graph analysis.
- Runtime/taint execution or dynamic tracing.
- Automatic synonym generation via LLM.
- Replacing existing rule IDs in score rubric in this phase.
- Cross-repo scanner plugins.

## 4. Users & Use Cases

Primary Users / Roles (Torus/LTI roles; e.g., Instructor, Author, Student, Admin).

- Platform engineers (maintainers of PrivSignal in CI).
- Privacy reviewers (evaluate risk deltas).
- Application engineers (consume findings in PR review).
- Secondary: security/compliance stakeholders.

Use Cases / Scenarios: Short narratives (1–3 paragraphs) or bullets.

- A PR logs `submitted_emails` and `invitee_emails`; scanner should map to PRD token `email` via normalized/alias match and classify with transparent confidence.
- A PR writes to DB through `Persistence.append_step/2`; scanner should infer DB sink classification from local wrapper summary and maintain deterministic results.
- A PR sends HTTP payload built in local variables and `Jason.encode!`; scanner should trace payload provenance and emit `indirect_payload_ref` evidence.
- CI consumers should receive higher-recall findings with explicit evidence and confidence semantics.

## 5. UX / UI Requirements

Key Screens/States: List and short description per screen/state.

- CLI output states only (no new UI screens):
  - `mix priv_signal.scan` markdown output includes confidence tier and evidence chain summary.
  - JSON lockfile/findings include new evidence types and confidence tier fields.

Navigation & Entry Points: Where in Torus this lives (menus, context actions).

- N/A (CLI and artifact outputs).
- Entry points remain `mix priv_signal.scan`, `mix priv_signal.diff`, `mix priv_signal.score`.

Accessibility: WCAG 2.1 AA; keyboard-only flows; screen-reader expectations; alt-text and focus order; color contrast.

- For CLI/Markdown artifacts, ensure plain-text readability, consistent heading order, and no color-only semantics.

Internationalization: Text externalized, RTL readiness, date/number formats.

- N/A for this backend-focused feature; maintain locale-neutral machine-readable outputs.

Screenshots/Mocks: Reference pasted images (e.g., ![caption](image-1.png)).

- No mock assets provided.

## 6. Functional Requirements

| ID | Description | Priority (P0/P1/P2) | Owner |
|---|---|---|---|
| FR-001 | Scanner shall support token normalization pipeline (case/snake/camel splitting, plural singularization, optional prefix stripping) before PRD match evaluation. | P0 | Engineering |
| FR-002 | Scanner shall support config-driven PRD aliases/synonyms in `priv_signal.yml` with schema validation. | P0 | Engineering |
| FR-003 | Scanner shall classify PRD token evidence confidence source as `exact`, `normalized`, or `alias`. | P0 | Engineering |
| FR-004 | Database scanner shall support wrapper-aware detection via `scanners.database.wrapper_modules` and `wrapper_functions` configuration. | P0 | Engineering |
| FR-005 | Scanner shall build deterministic intra-module function summaries marking local functions as `db_read`/`db_write` when they contain `Repo.*` operations. | P0 | Engineering |
| FR-006 | Calls to summarized wrapper functions shall emit inherited DB sink findings with traceable evidence. | P0 | Engineering |
| FR-007 | HTTP scanner shall track intra-function payload provenance across assignments and common builders (`Map.put`, `Map.merge`, map/keyword literals, `Jason.encode!`). | P0 | Engineering |
| FR-008 | HTTP sink findings shall include new evidence type `indirect_payload_ref` containing variable chain lineage. | P0 | Engineering |
| FR-009 | Findings shall expose staged confidence model: `confirmed`, `probable`, `possible`. | P0 | Engineering |
| FR-010 | JSON/Markdown output contracts shall include new fields/evidence while remaining deterministic and backward-compatible where feasible. | P1 | Engineering |
| FR-011 | Fixture-based regression suites shall be added for pluralized/derived names, DB wrappers, and HTTP prebuilt payloads. | P0 | QA + Engineering |

## 7. Acceptance Criteria (Testable)

AC-001 (FR-001, FR-003)
Given PRD token `email`
When scanner analyzes `submitted_emails` and `userEmail`
Then scanner emits findings linked to `email` with confidence source `normalized`.

AC-002 (FR-002, FR-003)
Given alias config mapping `invitee_email` -> `email`
When scanner analyzes key `invitee_email`
Then scanner emits matched finding with confidence source `alias`.

AC-003 (FR-004, FR-005, FR-006)
Given module-local function `Persistence.append_step/2` that calls `Repo.insert/1`
When scanner analyzes callsites to `Persistence.append_step/2`
Then scanner emits `database_write` findings with inherited wrapper evidence.

AC-004 (FR-007, FR-008)
Given HTTP payload is assigned to a variable and then encoded via `Jason.encode!`
When payload contains PRD-linked fields
Then scanner emits HTTP finding with `indirect_payload_ref` evidence showing variable chain.

AC-005 (FR-009)
Given direct field access evidence exists
When finding is emitted
Then confidence tier is `confirmed`.

AC-006 (FR-009)
Given only normalized/alias/provenance evidence exists without direct field access
When finding is emitted
Then confidence tier is `probable` or `possible` per configured thresholds.

AC-007 (FR-010)
Given identical code+config input
When scanner runs repeatedly
Then JSON/Markdown findings are byte-stable in ordering and IDs.

AC-008 (FR-011)
Given regression fixtures for each limitation class
When CI executes scanner tests
Then all new fixtures pass and prevent regression.

## 8. Non-Functional Requirements

Performance & Scale: targets for latency (p50/p95), throughput, and expected concurrency; LiveView responsiveness; pagination/streaming if needed.

- Scanner runtime overhead from new matching/provenance shall be bounded:
  - p50 scan duration increase <= 15%
  - p95 scan duration increase <= 25%
  - memory increase <= 20% for target fixture size.
- Preserve current file-parallel behavior and concurrency caps.

Reliability: error budgets, retry/timeout behavior, graceful degradation.

- Parse/provenance failures must degrade gracefully to baseline behavior (no crash).
- No non-deterministic external dependencies.

Security & Privacy: authentication & authorization (Torus + LTI roles), PII handling, FERPA-adjacent considerations, rate limiting/abuse protection.

- No runtime PII values in logs or report artifacts.
- Evidence shall reference identifiers/tokens/AST lineage only.
- Config-driven aliases must be repository-controlled and auditable.

Compliance: accessibility (WCAG), data retention, audit logging.

- Artifact outputs remain text-accessible and machine-readable.
- Changes must preserve existing audit/traceability properties in outputs.

Observability: telemetry events, metrics, logs, traces; AppSignal dashboards & alerts to add/modify.

- No telemetry or dashboard changes are required in this scope.

## 9. Data Model & APIs

Ecto Schemas & Migrations: new/changed tables, columns, indexes, constraints; sample migration sketch.

- No DB schema changes expected (CLI static analysis feature).

Context Boundaries: which contexts/modules change (e.g., Oli.Delivery.Sections, Oli.Resources, Oli.Publishing, Oli.GenAI).

- PrivSignal codepaths:
  - `PrivSignal.Scan.Inventory`
  - `PrivSignal.Scan.Scanner.Evidence`
  - `PrivSignal.Scan.Scanner.Database`
  - `PrivSignal.Scan.Scanner.HTTP`
  - scanner classifier/output modules
  - config schema/loader.

APIs / Contracts: new/updated functions, JSON shapes, LiveView events/assigns, REST/GraphQL (if any).

- `priv_signal.yml` additions (scanner config):
  - `matching.aliases` map (or equivalent scanner-scoped alias map)
  - `scanners.database.wrapper_modules` list
  - `scanners.database.wrapper_functions` list.
- Finding payload additions:
  - confidence source/tier fields
  - evidence type `indirect_payload_ref` with lineage chain.

Permissions Matrix: role × action table.

| Role | Action |
|---|---|
| Repo Maintainer | Configure aliases/wrappers in `priv_signal.yml` |
| CI Runner | Execute scan/diff/score in CI |
| Reviewer | Consume finding confidence/evidence outputs |

## 10. Integrations & Platform Considerations

LTI 1.3: launch flows, roles, deep-linking/content-item implications.

- Not directly applicable; scanner analyzes repository code artifacts independent of LTI runtime.

GenAI (if applicable): model routing, registered_models, completions_service_configs, Dialogue.Server, fallback models, rate limiting, cost controls, redaction.

- Not applicable; feature remains deterministic and local (no LLM dependency).

Caching/Perf: SectionResouseDepot or other caches; invalidation strategy; pagination and N+1 prevention.

- Optional per-file memoization for provenance analysis allowed; must remain per-run scoped.
- No persistent cache required for v1 rollout.

Multi-Tenancy: project/section/institution boundaries; config scoping (per-project, per-section).

- Configuration remains per-repository (`priv_signal.yml`), no tenant-runtime coupling.

## 11. Feature Flagging, Rollout & Migration

Flagging: name(s), default state, scope (project/section/global).

- No feature flags are required in this scope.

Data Migrations: forward & rollback steps; backfills.

- No data migration.
- Rollback by reverting scanner matching changes and/or disabling aliases/wrappers.

Rollout Plan: canary cohort, metrics to monitor, kill-switch.

- Rollout is standard merge/release flow.

Telemetry for Rollout: adoption & health counters.

- No rollout telemetry additions are required in this scope.

## 12. Analytics & Success Metrics

North Star / KPIs: define how success is measured.

- Recall uplift on staged Torus scenarios (target >= 80% of previously missed intended findings detected).
- Precision guardrail (target <= 15% increase in reviewer-rejected findings during canary).
- Determinism invariant maintained (0 nondeterminism regressions in property tests).

Event Spec: name, properties, user/section/project identifiers, PII policy.

- No event spec changes are required in this scope.

## 13. Risks & Mitigations

- Risk: false positives increase from fuzzy matching.
  - Mitigation: alias allowlist and confidence tiering with fixture-based regression checks.
- Risk: provenance analysis slows scans.
  - Mitigation: intra-function scope only and bounded builder support.
- Risk: wrapper detection over-matches helper functions.
  - Mitigation: explicit wrapper config + function summary constraints + evidence trace.
- Risk: output contract drift breaks downstream tooling.
  - Mitigation: versioned contract tests and additive fields first.

## 14. Open Questions & Assumptions

Assumptions

- `priv_signal.yml` may be extended with additive keys for aliases/wrappers/matching mode.
- Teams prefer explicit config over implicit fuzzy heuristics.
- Intra-module wrapper summarization is sufficient for initial rollout.

Open Questions

- Should alias config be global or scanner-specific namespaces?
- Should confidence tier thresholds be configurable or fixed defaults initially?
- Do we need a dedicated output contract version bump for new evidence payload fields?

## 16. QA Plan

Automated: unit/property tests, LiveView tests, integration tests, migration tests.

- Unit tests:
  - normalization (plural/case/prefix variants)
  - alias resolution
  - wrapper summary inference
  - provenance chain extraction.
- Unit fixture tests:
  - pluralized/derived token names
  - DB wrapper indirection
  - HTTP prebuilt/encoded payload lineage.
- No integration, property, or migration testing in this scope.

Manual: key exploratory passes, regression areas, accessibility checks.

- Manual QA is out of scope; focus is automated unit tests only.

## 17. Definition of Done

- [ ] `priv_signal.yml` schema supports aliases/wrappers/matching mode with validation.
- [ ] Token normalization + alias matching implemented with confidence source tagging.
- [ ] Wrapper-aware DB detection implemented (intra-module scope).
- [ ] HTTP provenance + `indirect_payload_ref` evidence implemented.
- [ ] Confidence tiers (`confirmed/probable/possible`) emitted consistently.
- [ ] Fixture-based regression suites pass for all three limitation classes.
- [ ] `docs/classification_registry.md` updated to reflect new classifications/evidence semantics.
- [ ] Rollout and rollback instructions documented.
