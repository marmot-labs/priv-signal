# PrivSignal Privacy-Relevant Data (PRD) Ontology v1 — PRD

## 1. Overview

Feature Name

PrivSignal Privacy-Relevant Data (PRD) Ontology v1

Summary: PrivSignal will replace its PII-only classification model with a broader Privacy-Relevant Data (PRD) ontology that captures direct identifiers, persistent pseudonymous identifiers, behavioral signals, inferred attributes, and sensitive context indicators. YAML inventory will be authoritative for PRD nodes, and scanning will discover evidence and flows for those nodes only. The scan/diff architecture, command surface, and runtime topology remain largely unchanged; this feature primarily expands identifier classes and reporting semantics. The feature remains on v1 schema/contracts only, with no backward compatibility or migration obligations because the software has not been released.

Links: Issues, epics, design files, related docs

- Related docs: `docs/features/identifiers/informal.md`
- Related docs: `docs/features/enhanced_scan/informal.md`
- Issues/epics/design files: none provided in current input

## 2. Background & Problem Statement

Current behavior / limitations.

- Current scanner framing is PII-centric and cannot consistently capture modern privacy risk introduced by linkable identifiers, behavioral telemetry, and inferred model outputs.
- Existing output structures are too narrow for meaningful trigger semantics such as inferred profiling export or identifier linkage escalation.
- PII-only scope under-detects privacy-relevant drift in analytics, ML, and engagement flows.
- Inventory authority is currently underspecified; this risks accidental scope drift into noisy auto-discovery.
- Current core scan/diff execution flow is already viable and should not be redesigned for this feature.

Authoritative model principle:

- The PRD inventory is explicitly declared in repository YAML, and scanning discovers evidence and flows for that inventory rather than discovering the full universe of PRD in code.

Who is affected

- Privacy/security engineers reviewing code and release risk.
- Maintainers operating CI checks and interpreting trigger output.
- Product and compliance stakeholders who rely on meaningful risk signals.

Why now (trigger, dependency, business value)?

- PrivSignal is at pre-release stage, creating a low-cost window for architectural correction.
- Backward compatibility constraints are intentionally removed, enabling a clean ontology and artifact redesign.
- This change materially improves risk detection quality without requiring heavy dynamic analysis.

## 3. Goals & Non-Goals

Goals: Bullet list of outcomes; measurable where possible.

- Introduce a production ontology with exactly five PRD classes in v1.
- Treat repository YAML inventory as the source of truth for PRD nodes and classes.
- Emit deterministic data node and flow artifacts that support richer diff triggers.
- Support structural triggers for inferred attributes, behavioral persistence, external profiling export, and identifier linkage.
- Achieve deterministic repeatability: same repo state produces byte-equivalent classification artifacts.
- Keep config/artifact contracts at v1 only and enforce them strictly.
- Preserve existing scan/diff operational workflow while expanding only identifier typing and reporting behavior.

Non-Goals: Explicitly out of scope to prevent scope creep.

- Full semantic or causal privacy harm modeling.
- Dynamic runtime taint tracking.
- Narrative-construction inference over longitudinal user histories.
- Automated legal conclusions (GDPR/FERPA determinations) beyond structural signaling.
- Silent auto-addition of new PRD nodes into inventory from AST observations.

## 4. Users & Use Cases

Primary Users / Roles

- CLI users running `mix priv_signal.scan` and `mix priv_signal.diff`.
- Engineering teams reviewing PR diff risk.
- Privacy reviewers interpreting trigger causes.

Use Cases / Scenarios: Short narratives (1–3 paragraphs) or bullets.

- A developer defines `engagement_score` in YAML inventory as `inferred_attribute` and adds persistence usage in code. The scanner finds evidence and flow paths, and the diff engine raises a profiling-surface trigger.
- A service links `user_id` with `mental_health_category`. The diff detects new linkage between `persistent_pseudonymous_identifier` and `sensitive_context_indicator` and emits elevated reassessment signal.

## 5. UX / UI Requirements

Key Screens/States: List and short description per screen/state.

- CLI success output: summary counts by PRD class, trigger counts, and artifact output path.
- CLI warning output: low-confidence classifications and rationale summary.
- CLI failure output: malformed config/schema errors with actionable remediation.
- Machine-readable output state: JSON artifact and lockfile suitable for diffing in CI.

Navigation & Entry Points: Where in the system this lives (menus, context actions).

- Entry via existing CLI commands in the `mix priv_signal.*` flow.
- Consumed in CI/CD pipelines as build artifact plus diff input.

Accessibility: WCAG 2.1 AA; keyboard-only flows; screen-reader expectations; alt-text and focus order; color contrast.

- No new web UI in scope; CLI output must remain text-first and parseable.
- Output severity labels must not rely on color alone.
- Structured output mode must support screen-reader-friendly linear reading order.

Internationalization: Text externalized, RTL readiness, date/number formats.

- Human-readable CLI strings remain English-only in v1.
- JSON artifact keys are language-neutral and stable.
- Numeric fields use machine-friendly formats independent of locale.

Screenshots/Mocks: Reference pasted images (e.g., ![caption](image-1.png)).

- No screenshots or mocks provided.

## 6. Functional Requirements

| ID | Description | Priority (P0/P1/P2) | Owner |
|---|---|---|---|
| FR-001 | System SHALL define exactly five PRD classes: `direct_identifier`, `persistent_pseudonymous_identifier`, `behavioral_signal`, `inferred_attribute`, `sensitive_context_indicator`. | P0 | Engineering |
| FR-002 | System SHALL treat repository PRD YAML inventory as the authoritative list of PRD data nodes included in artifact `data_nodes`. | P0 | Engineering |
| FR-003 | System SHALL classify inventory entries into one of the five PRD classes using deterministic rules under the v1 schema only. | P0 | Engineering |
| FR-004 | System SHALL use static AST heuristics to validate and match inventory entries in code and to discover evidence/flow paths for those entries. | P0 | Engineering |
| FR-005 | System SHALL NOT infer, propose, or auto-add inventory entries beyond explicit YAML definitions. | P0 | Engineering |
| FR-006 | System SHALL emit artifact JSON with `data_nodes` (from YAML inventory) and `flows` (from observed code evidence), including class and sensitivity metadata. | P0 | Engineering |
| FR-007 | System SHALL produce deterministic output for identical repo state/config (ordering, IDs, stable schema). | P0 | Engineering |
| FR-008 | System SHALL detect and emit triggers for: new inferred attribute, behavioral signal persistence, inferred attribute external transfer, and new linkage to sensitive context. | P0 | Engineering |
| FR-009 | System SHALL require v1 config/artifact schemas only and SHALL NOT support any alternate schema versions. | P0 | Engineering |
| FR-010 | System SHALL fail fast with clear error messages when input does not conform to the v1 schema. | P0 | Engineering |
| FR-011 | System SHALL expose confidence/evidence for non-obvious classifications to support reviewer interpretation. | P1 | Engineering |
| FR-012 | System SHALL preserve diff-based operation and avoid mandatory runtime instrumentation. | P0 | Engineering |
| FR-013 | System SHALL preserve existing command-level workflow (`mix priv_signal.scan` and `mix priv_signal.diff`) while extending identifier class handling and reporting outputs. | P0 | Engineering |

## 7. Acceptance Criteria (Testable)

AC-001 (FR-001)
Given a valid scan run
When ontology metadata is initialized
Then exactly five classes are available and class names match the required identifiers.

AC-002 (FR-002, FR-003)
Given `priv-signal.yml` contains an inventory entry for `user_id` scoped to `Oli.Delivery.Sections.Enrollment.user_id`
When classification runs
Then the entry is classified as `persistent_pseudonymous_identifier` and included in artifact `data_nodes`.

AC-003 (FR-005, FR-006)
Given engagement_score appears in code but no inventory entry exists
When scan runs
Then the artifact SHALL NOT include a data_node for engagement_score, and the run SHALL remain successful.

AC-004 (FR-005, FR-011)
Given a scan finding matches an inventory-defined identifier through non-trivial heuristic evidence
When artifact output is produced
Then output includes confidence and evidence metadata, and no new inventory entry is inferred or added.

AC-005 (FR-006)
Given a successful scan
When artifact is written
Then JSON contains `data_nodes` and `flows`, each `data_node` comes from YAML inventory, and each node includes `name`, `class`, and `sensitive` fields.

AC-006 (FR-007)
Given unchanged code/config and tool version
When scan runs twice
Then output artifacts are byte-identical.

AC-007 (FR-008)
Given a PR introduces a new `risk_score` external flow
When diff trigger engine executes
Then a trigger indicating inferred attribute external transfer is emitted.

AC-008 (FR-008)
Given a PR links `user_id` with `mental_health_category` in an observed flow
When diff trigger engine executes
Then a trigger indicating linkage escalation to sensitive context is emitted.

AC-009 (FR-009, FR-010)
Given non-v1 YAML/schema input
When scan runs
Then command fails with an explicit unsupported-schema error.

AC-010 (FR-013)
Given the feature is enabled
When developers run `mix priv_signal.scan` and `mix priv_signal.diff`
Then commands continue to operate with the same workflow, while outputs include and honor the expanded identifier classes.

## 8. Non-Functional Requirements

Performance & Scale: targets for latency (p50/p95), throughput, and expected concurrency; LiveView responsiveness; pagination/streaming if needed.

- CLI scan latency target on reference repo: p50 <= 8s, p95 <= 20s.
- Diff trigger phase target: p50 <= 2s, p95 <= 5s for typical PR-sized diffs.
- Throughput target for CI: sustain 20 sequential runs/hour per runner without memory growth >10% baseline.
- Peak memory target: <= 1.5x current PII scan baseline on same repo revision.
- No LiveView changes in scope.

Reliability: error budgets, retry/timeout behavior, graceful degradation.

- Scanner command success rate target: >= 99% for valid inputs in CI.
- Classification failure of one candidate must not crash full scan; emit partial warning and continue.
- Existing scan/diff command invocation patterns remain unchanged.

Security & Privacy: authentication & authorization, PII handling, FERPA-adjacent considerations, rate limiting/abuse protection.

- No new authentication surface; local CLI execution model unchanged.
- Artifacts must avoid raw secret values and redact high-risk literals when captured as evidence.
- Treat student-related sensitive indicators as high-risk signals for reassessment workflows.

Compliance: accessibility (WCAG), data retention, audit logging.

- CLI output remains accessible, non-color-dependent, and script-friendly.
- Generated artifacts follow existing retention policy in CI artifact storage.
- Scan runs must emit auditable logs for command version, config hash, and result status.

Observability: additional telemetry/AppSignal reporting is out of scope for this feature.

## 9. Data Model & APIs

Ecto Schemas & Migrations: no database migrations or migration steps are required for this feature.

- No Postgres schema changes are required; artifact/config contracts remain v1-only.
- Internal structs/modules should introduce typed ontology enums/atoms for five PRD classes.
- Optional future DB persistence is out of scope.

Context Boundaries: which contexts/modules change (e.g., Oli.Delivery.Sections, Oli.Resources, Oli.Publishing, Oli.GenAI).

- `PrivSignal.Scan` / scan pipeline orchestration.
- `PrivSignal.Identifier` or equivalent classification modules.
- `PrivSignal.Flow` diff trigger modules.
- `PrivSignal.Config` schema parser/validator.

APIs / Contracts: new/updated functions, JSON shapes, LiveView events/assigns, REST/GraphQL (if any).

- New/updated internal contracts (illustrative):
- `classify_inventory_node(node, context) :: {:ok, classification} | {:error, reason}`
- `classification = %{name: String.t(), data_class: atom(), confidence: float(), rationale: String.t(), sensitive: boolean()}`
- `emit_artifact(nodes, flows, meta) :: :ok | {:error, reason}`
- JSON artifact shape:
- `data_nodes[]`: `name`, `class`, `sensitive`, optional `confidence`, `rationale`, `evidence` (inventory-backed only)
- `flows[]`: `from`, `to`, `boundary`, optional `transport`, `module`, `line`
- No external REST/GraphQL API changes.

Permissions Matrix: role × action table.

| Role | Run scan | Read artifact | Change config schema | Override classification rules |
|---|---|---|---|---|
| Developer | Yes | Yes | Yes (repo write) | Yes (repo write) |
| CI Service Account | Yes | Yes | No | No |
| Security Reviewer | No (unless repo access) | Yes | No | No |
| Maintainer | Yes | Yes | Yes | Yes |

## 10. Integrations & Platform Considerations

## 11. Feature Flagging, Rollout & Migration

Flagging: no feature flags are required for this feature.

Environments: no staged/canary rollout requirement; ship as standard delivery once acceptance criteria pass.

Data Migrations: none required.

- No schema migration or conversion workflow is required in this pre-release phase.

## 12. Analytics & Success Metrics

North Star / KPIs: define how success is measured.

- KPI-1: >= 95% of YAML inventory entries successfully classified and mapped to PRD classes on scan.
- KPI-2: <= 10% false-positive rate in sampled `inferred_attribute` and `behavioral_signal` findings.
- KPI-3: >= 95% of scan runs produce deterministic artifact diff stability across reruns.
- KPI-4: increase in actionable trigger types vs PII-only baseline.

Event Spec: name, properties, user/section/project identifiers, PII policy.

- No new analytics/telemetry event requirements for this feature.

## 13. Risks & Mitigations

- Technical risk: over-classification noise in heuristic model.
- Mitigation: confidence scoring, rationale output, curated heuristic allow/deny rules.
- Product risk: trigger fatigue from increased finding volume.
- Mitigation: severity tiers and diff-only gating in CI.
- Operational risk: scan time increase impacts pipeline duration.
- Mitigation: perf budgets and AST traversal reuse.
- Change risk: intentional breaking schema changes confuse adopters.
- Mitigation: hard fail messages and clear v1-only schema documentation.

## 14. Open Questions & Assumptions

Clearly separate assumptions (made by this PRD) from open questions needing resolution.

Assumptions

- No backward compatibility is required for YAML/config/lockfile/artifact formats.
- Existing PII detection logic will be retained as signal input but remapped under PRD ontology.
- YAML inventory is authoritative; AST-only discoveries that are not in inventory are ignored for inventory expansion.
- CLI-first UX is sufficient for v1.

Open Questions

- Should `sensitive_context_indicator` imply default high severity in all triggers, or severity depend on boundary/linkage context?
- What exact confidence threshold should separate warning-only vs CI-blocking recommendations?
- Is there a need for per-repository custom ontology aliases in v1.1?

## 15. Timeline & Milestones (Draft)

- Phase 1 (Week 1): Finalize ontology constants, v1 parser/schema rules, artifact contract updates. Owner: Engineering.
- Phase 2 (Week 2): Implement inventory classification and AST matching heuristics + deterministic output constraints + unit tests. Owner: Engineering.
- Phase 3 (Week 3): Implement trigger engine expansions + integration tests. Owner: Engineering.
- Phase 4 (Week 4): Validate KPIs/NFRs and finalize operational docs. Owner: Engineering + QA.

Dependencies

- Availability of representative fixture repos for false-positive sampling.

## 16. QA Plan

Automated: unit/property tests, LiveView tests, integration tests.

- Unit tests: class mapping rules, confidence/rationale requirements, schema validation failures.
- Property tests: deterministic ordering and stable serialization of nodes/flows.
- Integration tests: end-to-end scan on fixtures covering all five classes and four trigger types.
- Schema tests: explicit failure behavior for any non-v1 schema input.
- No LiveView tests required (no UI changes).

Manual: key exploratory passes, regression areas, accessibility checks.

- Validate CLI readability with and without color support.
- Validate warning/error clarity for unsupported non-v1 schema input.
- Regression passes on existing scan commands and CI invocation paths.

Load/Perf: how we’ll verify NFRs.

- Benchmark scan and diff phases across small/medium/large fixture repos.
- Run 50 repeated scans on fixed commit to verify p50/p95 and memory targets.
- Compare against pre-change baseline to confirm <= 1.5x memory overhead.

## 17. Definition of Done

- [ ] Docs updated (`docs/features/identifiers/prd.md`, related references)
- [ ] Deterministic artifact output validated by automated tests
- [ ] Non-v1 schema hard-fail behavior implemented
- [ ] Trigger expansions implemented and verified for all required trigger types
- [ ] QA sign-off completed (automated + manual)
