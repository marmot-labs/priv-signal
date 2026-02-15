## 1. Overview

Feature Name
PrivSignal - Phase 4: Expanded Inventory Surface Area (High ROI Sinks and Sources)

Summary: Phase 4 expands PrivSignal's deterministic AST scanner beyond logging to cover high-risk production privacy surfaces: outbound HTTP, controller responses, telemetry/analytics, database reads and writes, and LiveView UI exposure. The feature emits additional node candidates only, preserving current proto-flow v1 inference behavior while materially increasing real-world privacy signal coverage. The outcome is higher ROI detection with stable, explainable evidence and configurable scanner categories.

Links: `docs/features/scan/fdd.md`, `docs/features/scan/plan.md`, `docs/features/scan/phase0_traceability.md`, `lib/priv_signal/scan/runner.ex`, `lib/priv_signal/infer/runner.ex`

## 2. Background & Problem Statement

Current behavior / limitations.
PrivSignal scan output is currently centered on logging sinks from `PrivSignal.Scan.Logger`, and infer-node adaptation is implemented through `PrivSignal.Infer.ScannerAdapter.Logging`. This leaves major privacy exposure surfaces unmodeled, especially outbound integrations, response rendering, telemetry export, and UI exposure pathways.

Who is affected
- Privacy/security engineers running CI checks for PII exposure risk.
- Developers and reviewers who need actionable sink/source evidence during PR review.
- Compliance stakeholders relying on deterministic inventory evidence.

Why now (trigger, dependency, business value)?
- Proto-flow v1 exists and can immediately benefit from more node coverage without requiring new inference logic.
- Current logging-only coverage misses many incidents that happen via third-party HTTP, telemetry SDKs, and response payloads.
- Expanding to high-ROI surfaces provides immediate risk-reduction value while maintaining deterministic, explainable behavior.

## 3. Goals & Non-Goals

Goals:
- Add deterministic scanners for five categories: HTTP client calls, controller responses, telemetry/analytics, database reads/writes, and LiveView exposure.
- Emit stable node candidates with normalized module/function/file context, confidence, and evidence for all new categories.
- Keep proto-flow inference logic unchanged; only expand node surface area consumed by infer.
- Make each scanner category independently configurable via `priv-signal.yml` (`enabled` flags and category-specific overrides).
- Maintain scan determinism and runtime performance within Phase 1 scan performance bounds.

Non-Goals:
- Interprocedural taint analysis or transform chaining.
- Cross-module or cross-process inference (including async jobs).
- WebSocket boundary modeling beyond LiveView.
- GraphQL server resolver modeling and Phoenix Channels modeling in this phase.
- Runtime policy enforcement/redaction changes.

## 4. Users & Use Cases

Primary Users / Roles
- Developer: runs `mix priv_signal.scan` locally or in CI and remediates findings.
- Privacy Engineer: tunes scanner config, validates coverage, and tracks risk trends.
- Reviewer/QA: verifies that newly introduced integrations or response payloads are represented in findings.

Use Cases / Scenarios:
- A team adds a Stripe integration through `Req.post/2`; Phase 4 emits an external HTTP sink node with evidence at the call site, enabling inferred flow links from declared PII fields.
- A controller action renders `json(conn, %{email: user.email})`; Phase 4 emits an `http_response` sink node so exposure is represented even when no log statement exists.
- A LiveView pushes PII in `assign/3` and `push_event/3`; Phase 4 emits `liveview_render` sinks so UI exposure risk is represented.
- A module reads records via `Repo.get/3` and persists via `Repo.insert/2`; Phase 4 emits `database_read` source and `database_write` sink nodes to anchor storage-related flows.

## 5. UX / UI Requirements

Key Screens/States: List and short description per screen/state.
- CLI success output: includes category-level scan counts and findings summary in JSON/Markdown output.
- CLI partial failure output: reports parse/timeout errors by file while still returning deterministic findings from successfully scanned files.
- Config validation errors: explicit schema messages when `scanners` section is malformed.

Navigation & Entry Points: Where in the system this lives (menus, context actions).
- Entry point remains `mix priv_signal.scan` and infer pipeline consumption via `PrivSignal.Infer.Runner`.
- No new UI screens; output continues through existing scan and infer output writers.

Accessibility: WCAG 2.1 AA; keyboard-only flows; screen-reader expectations; alt-text and focus order; color contrast.
- N/A for web UI in this phase (CLI-only feature).
- Markdown output must remain semantic and plain-text readable for assistive tooling.

Internationalization: Text externalized, RTL readiness, date/number formats.
- Human-readable output strings remain English in this phase.
- JSON output remains locale-neutral and machine readable.

Screenshots/Mocks: Reference pasted images (e.g., ![caption](image-1.png)).
- No screenshots provided.

## 6. Functional Requirements

| ID | Description | Priority (P0/P1/P2) | Owner |
|---|---|---|---|
| FR-001 | Extend scanner architecture to support multiple deterministic category scanners in one file pass and aggregate findings into a single normalized finding list. | P0 | Engineering |
| FR-002 | Detect outbound HTTP client calls across built-in and configured wrapper modules; emit sink nodes with `role.kind=http`, `boundary` classification, confidence, and evidence. | P0 | Engineering |
| FR-003 | Detect controller response exposure calls (`json/render/send_resp/put_resp_body/send_file/send_download` and configured render helpers); emit sink nodes with `role.kind=http_response`. | P0 | Engineering |
| FR-004 | Detect telemetry/analytics export calls (`:telemetry`, AppSignal, Sentry, OpenTelemetry, and configured modules); emit sink nodes with `role.kind=telemetry`. | P0 | Engineering |
| FR-005 | Detect database reads as source nodes and writes as sink nodes for configured repo modules and common Ecto query/write APIs. | P0 | Engineering |
| FR-006 | Detect LiveView exposure via `assign`, render payloads, and `push_event`; emit sink nodes with `role.kind=liveview_render`. | P0 | Engineering |
| FR-007 | Add `scanners` YAML config section with per-category enablement and overrides (`additional_modules`, `repo_modules`, `internal_domains`, `additional_render_functions`). | P0 | Engineering |
| FR-008 | Preserve deterministic node identity and context normalization across all new categories, reusing stable ID generation and path normalization. | P0 | Engineering |
| FR-009 | Keep proto-flow v1 logic unchanged while ensuring new node kinds participate in existing flow-building eligibility checks where applicable. | P1 | Engineering |
| FR-010 | Emit category-aware telemetry and summary counters for scan health, adoption, and regression monitoring. | P1 | Engineering |
| FR-011 | Maintain backwards compatibility: existing configs without `scanners` continue to work with safe defaults. | P0 | Engineering |

## 7. Acceptance Criteria (Testable)

AC-001 (FR-001, FR-008)
Given a repository with deterministic input files and config
When `mix priv_signal.scan` runs twice on the same commit
Then output findings and node IDs are byte-for-byte stable (ordering and identity unchanged).

AC-002 (FR-002, FR-007)
Given source code with `Finch.request/3`, `Req.post/2`, and configured `MyApp.HTTP.call/2`
When scan runs with HTTP scanner enabled
Then scanner emits `sink` findings mapped to infer nodes with `role.kind=http` and includes evidence for matched call expressions.

AC-003 (FR-002)
Given outbound calls to `api.stripe.com` and `internal.myapp.com` with domain config present
When HTTP boundary classification executes
Then `api.stripe.com` is classified `external`, `internal.myapp.com` is `internal`, and unknown hosts default to `external` with lower confidence.

AC-004 (FR-003, FR-007)
Given controller actions using `json(conn, payload)`, `render(conn, ...)`, and configured `MyAppWeb.API.render_json/2`
When scan runs
Then each PII-bearing response call emits a `sink` finding that maps to infer node `role.kind=http_response` with boundary `external`.

AC-005 (FR-004)
Given code invoking `:telemetry.execute/3`, `Appsignal.set_user/2`, and `OpenTelemetry.set_attribute/3`
When scan runs
Then scanner emits telemetry sink findings with `role.kind=telemetry`, evidence, and confidence.

AC-006 (FR-005, FR-007)
Given code invoking configured repo module calls `Repo.get/3`, `Repo.one/2`, `Repo.insert/2`, and `Repo.update_all/3`
When scan runs with database scanner enabled
Then read calls emit `source` findings (`role.kind=database_read`) and write calls emit `sink` findings (`role.kind=database_write`).

AC-007 (FR-006)
Given LiveView modules using `assign/3`, `render/1`, and `push_event/3` with PII-bearing payloads
When scan runs
Then scanner emits sink findings that map to infer nodes with `role.kind=liveview_render`.

AC-008 (FR-007, FR-011)
Given a legacy config without `scanners` section
When config loads and scan runs
Then scan succeeds using default scanner settings and existing logging behavior remains intact.

AC-009 (FR-009)
Given Phase 4 nodes and proto-flow v1 enabled
When infer pipeline runs
Then flow-builder executes unchanged logic and can produce flows involving new sink/source node roles without regressions in existing logging-based flows.

AC-010 (FR-010)
Given scan and infer runs in CI
When telemetry is emitted
Then category counters, duration metrics, and error-type counters are present for dashboarding and alerting.

## 8. Non-Functional Requirements

Performance & Scale:
- Single AST traversal per file for all categories (no category-specific reparse passes).
- Performance target: p95 scan wall-clock regression <= 20% versus current logging-only baseline on the same repository and hardware profile.
- Concurrency behavior remains bounded by current runner caps; memory growth must be linear with file count, not quadratic.
- LiveView and controller detection must use pattern matching, not reflection.

Reliability:
- Scanner errors remain isolated per file; one file failure must not abort whole-run unless strict mode is enabled.
- Timeout and worker-exit behavior remains consistent with current `PrivSignal.Scan.Runner` semantics.
- Graceful degradation: disabled categories or missing optional libraries do not break run.

Security & Privacy:
- No runtime value capture; evidence is symbol/AST-level only.
- Output must not include raw PII values from source literals beyond what is already present in code references.
- Boundary classification must default conservatively (unknown host -> external).
- Abuse protection: no network calls or runtime execution during scanning.

Compliance:
- WCAG requirements apply only to generated markdown readability for this CLI phase.
- Auditability: findings include module/function/file/line and rule signal for traceability.
- Data retention aligns with existing CI artifact policy; no new persistent data stores introduced.

Observability:
- Add scan telemetry dimensions by category and node kind.
- Add AppSignal dashboards for scan duration, finding volume by category, and scan error rates.
- Add alerts for sudden drop-to-zero in expected category findings and elevated parse/timeout errors.

## 9. Data Model & APIs

Ecto Schemas & Migrations: new/changed tables, columns, indexes, constraints; sample migration sketch.
- No new Ecto schemas or database migrations in PrivSignal for Phase 4.
- The "database" category refers to static detection of host-application Ecto usage, not persistence in PrivSignal.

Context Boundaries: which contexts/modules change (e.g., Oli.Delivery.Sections, Oli.Resources, Oli.Publishing, Oli.GenAI).
- `PrivSignal.Scan.Runner`: orchestrates category scanners and aggregation.
- `PrivSignal.Scan.Logger` (or successor scanner modules): evolves from logging-only into category-aware scanning architecture.
- `PrivSignal.Config` and `PrivSignal.Config.Schema`: add `scanners` config structure and validation.
- `PrivSignal.Infer.ScannerAdapter.Logging` (and likely additional adapters): map new finding roles to infer nodes.
- `PrivSignal.Infer.Runner`: consumes expanded nodes without changing flow logic.

APIs / Contracts: new/updated functions, JSON shapes, LiveView events/assigns, REST/GraphQL (if any).
- Extend finding contract to carry category/role metadata needed for infer node mapping.
- Preserve output writer contracts (`scan` and `infer` JSON/Markdown) with additive fields only.
- Proposed additive config shape:

```yaml
scanners:
  logging:
    enabled: true
    additional_modules: []
  http:
    enabled: true
    additional_modules: []
    internal_domains: []
    external_domains: []
  controller:
    enabled: true
    additional_render_functions: []
  telemetry:
    enabled: true
    additional_modules: []
  database:
    enabled: true
    repo_modules: []
  liveview:
    enabled: true
    additional_modules: []
```

Permissions Matrix: role × action table.

| Role | Configure scanners | Run scan | View findings | Modify CI gating |
|---|---|---|---|---|
| Developer | Yes (repo config) | Yes | Yes | Yes (with repo permissions) |
| Privacy Engineer | Yes | Yes | Yes | Yes |
| Reviewer/QA | No (unless write access) | Yes | Yes | No |
| CI Service Account | No | Yes | Publishes artifacts | Enforces existing pipeline rules only |

## 10. Integrations & Platform Considerations

LTI 1.3: launch flows, roles, deep-linking/content-item implications.
- No direct LTI integration changes in PrivSignal.
- Scanner must still detect sinks/sources in host code paths that may include LTI controllers and LiveViews.

GenAI (if applicable): model routing, registered_models, completions_service_configs, Dialogue.Server, fallback models, rate limiting, cost controls, redaction.
- Not applicable; Phase 4 is deterministic and explicitly excludes LLM usage.

Caching/Perf: SectionResouseDepot or other caches; invalidation strategy; pagination and N+1 prevention.
- Cache per-file module classification and scanner category enablement to avoid repeated checks during AST traversal.
- No cross-run cache required in this phase.

Multi-Tenancy: project/section/institution boundaries; config scoping (per-project, per-section).
- PrivSignal remains repo-scoped; scanner config is per-repository (`priv-signal.yml`).
- Findings must remain code-location based and tenant-neutral; no cross-tenant runtime data is accessed.

## 11. Feature Flagging, Rollout & Migration

Flagging: name(s), default state, scope (project/section/global).
- Config-based flags under `scanners.<category>.enabled`.
- Default state: all Phase 4 categories enabled unless explicitly disabled.

Environments: dev/stage/prod gating.
- Gating via config in each environment's repository/branch configuration.
- CI can run with category subsets during canary rollout.

Data Migrations: forward & rollback steps; backfills.
- No DB migrations.
- Forward: add `scanners` config keys; keep defaults for missing keys.
- Rollback: disable new categories and continue logging-only behavior.

## 12. Analytics & Success Metrics

North Star / KPIs: define how success is measured.
- Increase in high-confidence privacy-relevant node coverage per repository.
- Reduction in "unmodeled sink" incidents reported by reviewers.
- Stable CI scan reliability with acceptable runtime regression.

Event Spec: name, properties, user/section/project identifiers, PII policy.
- `[:priv_signal, :scan, :category, :summary]`
  - Properties: `category`, `enabled`, `finding_count`, `duration_ms`, `error_count`.
- `[:priv_signal, :infer, :node, :kind]`
  - Properties: `node_type`, `role_kind`, `count`.
- Identifiers: repo slug and commit SHA (non-PII operational metadata).
- PII policy: never emit code values or extracted runtime payload contents.

## 13. Risks & Mitigations

- Risk: false positives increase and reduce trust.
  - Mitigation: confidence scoring, deterministic evidence signals, category toggles, and documented heuristics.
- Risk: performance regressions from broader pattern checks.
  - Mitigation: single-pass AST traversal, per-file caching, benchmark gating against baseline.
- Risk: config complexity causes misconfiguration.
  - Mitigation: strict schema validation with actionable errors and backward-compatible defaults.
- Risk: boundary misclassification for HTTP hosts.
  - Mitigation: conservative external default, explicit domain overrides, and confidence downgrade for unknowns.
- Risk: drift between scanner finding contract and infer adapter expectations.
  - Mitigation: contract tests for finding-to-node mapping and deterministic ID snapshot tests.

## 14. Open Questions & Assumptions

Assumptions (made by this PRD)
- Existing scan architecture will be extended (not replaced) so `mix priv_signal.scan` and infer outputs stay backward compatible.
- New category findings can be represented with additive fields in existing finding/node contracts.
- Performance baseline for "Phase 1 bounds" will be measured against current `main` logging-only scan on representative repos.
- Domain classification can rely on static URL literals and configured domain lists in this phase.

Open Questions (need resolution)
- Resolved (2026-02-15): `external_domains` takes precedence over `internal_domains` when both match.
- Resolved (2026-02-15): controller and LiveView sinks emit findings only when explicit PII evidence is present.
- Resolved (2026-02-15): unified infer scanner adapter path is used for all category findings.
- Remaining: confirm any additional downstream JSON consumer requirements beyond current lockfile schema v1.2 tests.

## 15. Timeline & Milestones (Draft)

- N/A

## 16. QA Plan

Automated: unit/property tests, LiveView tests, integration tests, migration tests.
- Unit tests per category scanner for positive/negative AST patterns.
- Config schema tests for `scanners` defaults, malformed values, and backward compatibility.
- Infer adapter contract tests for node role mapping and stable IDs.
- Integration tests: end-to-end scan -> infer flow generation on mixed-category fixtures.
- Determinism tests: repeated runs must match exactly.
- No migration tests required (no DB migrations).

Manual: key exploratory passes, regression areas, accessibility checks.
- Run scan on at least one Phoenix app fixture containing all five categories and inspect Markdown output clarity.
- Regression pass on logging-only repos to verify no behavior break.
- Validate CLI output readability in terminal and markdown viewers.

## 17. Definition of Done

- [ ] PRD/FDD/plan updated and consistent for Phase 4 scope.
- [ ] `scanners` config validation implemented with backward-compatible defaults.
- [ ] All five scanner categories emit deterministic findings with evidence and confidence.
- [ ] Infer node mapping supports new role kinds without changing proto-flow algorithm behavior.
- [ ] Scan/infer outputs (JSON and Markdown) include new category findings without breaking existing consumers.
- [ ] AppSignal dashboards and alerts updated for category-level health and regressions.
- [ ] Automated test suite passes, including determinism and compatibility coverage.
- [ ] Canary rollout completed with documented rollback procedure and kill-switch validation.
