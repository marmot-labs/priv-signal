# Proto Flow Inference v1 (Single-Scope, Same-Unit) — PRD

## 1. Overview

**Feature Name**

Proto Flow Inference v1 (Single-Scope, Same-Unit)

**Summary**

PrivSignal adds a deterministic inference step that converts Phase 1 PII inventory nodes into coarse, privacy-relevant Proto Flows within a single unit of work (function/controller action/LiveView handler). The capability helps developers quickly identify likely PII movement to sinks (loggers, HTTP emitters, telemetry) without requiring interprocedural taint analysis. Output is stable, explainable, and diff-friendly for CI/CD review workflows.

**Links**

- Epic: `docs/features/inferred_flows/informal.md`
- Related: `docs/features/enhanced_scan/prd.md`
- Architecture baseline: `docs/fdd.md`
- Product baseline: `docs/prd.md`

## 2. Background & Problem Statement

Phase 1 (`enhanced-scan`) produces deterministic PII node inventories with normalized identifiers and evidence, but does not summarize whether touched PII likely reaches sinks in a meaningful unit of work. Users currently must manually interpret node lists, which is slow and inconsistent during PR review.

Who is affected:

- Privacy/security engineers reviewing code changes for PII handling risk.
- Backend engineers who need actionable, explainable findings from scans.
- CI maintainers consuming machine-generated artifacts for downstream checks.

Why now:

- Proto Flow inference is the dependency for future diff-based privacy risk detection.
- Deterministic same-unit inference provides immediate value with low implementation risk.
- The team needs a stable intermediate abstraction before policy enforcement and multi-hop reasoning.

## 3. Goals & Non-Goals

**Goals**

- Infer Proto Flows using only same-unit evidence from existing Phase 1 node inventory.
- Keep behavior deterministic and rules-based, with zero LLM dependency.
- Serialize stable flow objects in `privsignal.json` with deterministic IDs and canonical ordering.
- Make every inferred flow explainable through explicit node evidence references.
- Favor recall over precision while keeping false positives bounded via confidence scoring.

**Non-Goals**

- Cross-function, cross-module, or whole-program dataflow/taint analysis.
- Path-sensitive variable tracking or exact execution tracing.
- Policy gating/blocking decisions based on flow output in this release.
- Manual flow authoring or override UX.
- LLM-assisted inference, scoring, or summarization.

## 4. Users & Use Cases

**Primary Users / Roles**

- `Maintainer`: runs `mix priv_signal.infer` locally/in CI and reviews diffs.
- `Privacy Reviewer`: evaluates inferred flows and confidence/evidence during PR review.
- `Platform Integrator`: consumes `privsignal.json` for dashboards or downstream automation.

**Use Cases / Scenarios**

- A controller action reads `user.email` and emits `Logger.info/1`; inference emits a flow linking source, entrypoint, and sink with evidence IDs.
- A LiveView `handle_event/3` touches PII and sends telemetry containing PII fields; inference emits a flow candidate with boundary and confidence.
- A diff introduces new sink usage in a function that already touches PII; resulting new/changed flows appear in artifact diff and review tooling.

## 5. UX / UI Requirements

**Key Screens/States**

- CLI success state: `mix priv_signal.infer` completes and writes updated `privsignal.json` containing `flows`.
- CLI no-flow state: command succeeds with empty `flows` array when no candidates are found.
- Review state: PR diff shows stable additions/removals/updates under `flows`.
- Diagnostic state: each flow includes enough evidence (`node_id`s) to explain inference outcome.

**Navigation & Entry Points**

- Primary entrypoint: existing CLI command `mix priv_signal.infer`.
- Output entrypoint: repository root artifact `privsignal.json` (same artifact as Phase 1 inventory output).

**Accessibility**

- WCAG 2.1 AA applies to any future rendered UI consumers; current CLI/artifact output must use machine-readable JSON with deterministic structure.
- If surfaced in web UI later: keyboard-only navigation, focus order, screen-reader labels, color contrast >= 4.5:1, non-color-only confidence cues.

**Internationalization**

- Artifact values use locale-neutral formats (ASCII keys, numeric confidence values, ISO-like stable identifiers).
- Human-readable strings in future UI consumers must be externalized and RTL-safe.

**Screenshots/Mocks**

- None provided.

## 6. Functional Requirements

| ID | Description | Priority (P0/P1/P2) | Owner |
|---|---|---|---|
| FR-001 | The infer pipeline SHALL read Phase 1 node inventory and evaluate candidates only within a single unit of work (same module + function/entrypoint context). | P0 | Engineering |
| FR-002 | The system SHALL infer a Proto Flow candidate when at least one PII-related node and at least one sink node co-occur in the same unit. | P0 | Engineering |
| FR-003 | The system SHALL support recognized entrypoints (controller action, LiveView callback, job handler) as flow entrypoint anchors when present. | P0 | Engineering |
| FR-004 | Each flow SHALL include: `id`, `source`, `entrypoint`, `sink`, `boundary`, `confidence`, and `evidence` (node IDs). | P0 | Engineering |
| FR-005 | Flow IDs SHALL be deterministic and derived from semantic identity fields (not run metadata). | P0 | Engineering |
| FR-006 | Confidence SHALL be computed by deterministic additive heuristics, clamped to `[0.0, 1.0]`, with fixed rounding strategy. | P0 | Engineering |
| FR-007 | Boundary SHALL default to `internal` and be set to `external` only when sink classification explicitly indicates external emission. | P1 | Engineering |
| FR-008 | Output ordering SHALL be canonical and stable across repeated runs on unchanged inputs. | P0 | Engineering |
| FR-009 | The command SHALL write inferred flows under top-level `flows` in `privsignal.json` without breaking existing node schema consumers. | P0 | Engineering |
| FR-010 | Flow evidence SHALL reference normalized node IDs only, never raw AST payloads or environment-dependent data. | P0 | Engineering |
| FR-011 | Inference SHALL run without introducing >10% p95 runtime regression versus Phase 1 scan baseline on representative repositories. | P1 | Engineering |
| FR-012 | The system SHALL emit AppSignal telemetry for inference start/end, candidate count, emitted flow count, and error count. | P1 | Engineering |

## 7. Acceptance Criteria (Testable)

- **AC-001 (FR-001, FR-002)**
  - Given a function scope containing one confirmed PII node and one logger sink node
  - When `mix priv_signal.infer` runs
  - Then exactly one flow candidate is emitted for that scope.

- **AC-002 (FR-003, FR-004)**
  - Given a Phoenix controller action context (`MyAppWeb.UserController.create/2`) with eligible nodes
  - When inference runs
  - Then emitted flow `entrypoint` equals `MyAppWeb.UserController.create/2` and contains all required fields.

- **AC-003 (FR-004, FR-010)**
  - Given an emitted flow
  - When inspecting `evidence`
  - Then each evidence element is a valid existing node ID and no raw AST snippets are present in flow payload.

- **AC-004 (FR-005, FR-008)**
  - Given unchanged source code and unchanged node inventory
  - When inference runs twice
  - Then flow IDs and serialized ordering are byte-for-byte identical.

- **AC-005 (FR-006)**
  - Given a candidate with additive contributions exceeding 1.0
  - When confidence is calculated
  - Then final confidence is exactly `1.0` (clamped).

- **AC-006 (FR-006)**
  - Given a candidate with contributions below 0.0
  - When confidence is calculated
  - Then final confidence is exactly `0.0` (clamped).

- **AC-007 (FR-007)**
  - Given a sink classified as internal logger
  - When inference runs
  - Then boundary is `internal`.

- **AC-008 (FR-007)**
  - Given a sink classified as outbound HTTP client
  - When inference runs
  - Then boundary is `external`.

- **AC-009 (FR-009)**
  - Given existing `privsignal.json` with `nodes`
  - When inference runs
  - Then output includes top-level `flows` while preserving existing node structure compatibility.

- **AC-010 (FR-011)**
  - Given the representative benchmark corpus
  - When comparing p95 runtime before/after enabling flow inference
  - Then p95 increase is <= 10%.

- **AC-011 (FR-012)**
  - Given a successful inference run
  - When telemetry is captured
  - Then AppSignal includes events/metrics for run duration, candidate count, and emitted flow count.

## 8. Non-Functional Requirements

**Performance & Scale**

- Target p50 inference overhead: <= 5% over Phase 1 baseline.
- Target p95 inference overhead: <= 10% over Phase 1 baseline.
- Throughput target: process at least 5k node records in < 3s on standard CI runner baseline used by this repo.
- Memory target: < 150 MB RSS delta during inference stage.
- Keep processing single-pass or near single-pass over grouped same-unit node sets; avoid N^2 joins.

**Reliability**

- Inference failure in one unit must not corrupt artifact; command should fail fast with actionable error and preserve previous artifact until successful write.
- Determinism is a reliability requirement: identical input must produce identical output.
- Timeout behavior: inherit command timeout defaults; inference stage should expose elapsed time telemetry.

**Security & Privacy**

- Respect repository-local scanning scope; do not exfiltrate code or artifacts.
- No additional secrets required; honor existing environment variable conventions.
- Flow payload must avoid raw PII values and include only semantic references/classifications.
- Sink/source labels should be metadata-only, not captured runtime data.

**Compliance**

- WCAG 2.1 AA compliance applies for any future GUI consumer of these flows.
- Artifact retention follows existing `privsignal.json` handling policy in CI.
- Auditability via deterministic IDs + evidence references to support review trails.

**Observability**
- N/A

## 9. Data Model & APIs

**Ecto Schemas & Migrations**

- No database schema or migration required for v1 (artifact-only output).
- Data contract change is `privsignal.json` schema extension with top-level `flows` array.

**Context Boundaries**

- Expected modules (indicative):
  - `PrivSignal.Scan` (input node inventory contract)
  - `PrivSignal.Infer` (new inference orchestration)
  - `PrivSignal.Infer.FlowBuilder` (candidate assembly + scoring)
  - `PrivSignal.Output` (stable serialization)
  - `PrivSignal.Telemetry` (instrumentation)

**APIs / Contracts**

- Internal function contract sketch:
  - `PrivSignal.Infer.run(nodes, opts) :: {:ok, [flow]} | {:error, reason}`
  - `PrivSignal.Infer.FlowBuilder.build(grouped_nodes, opts) :: [flow]`
  - `PrivSignal.Infer.Score.compute(candidate, weights) :: float()`
- JSON flow shape:

```json
{
  "id": "psf_<deterministic_hash>",
  "source": "Oli.Accounts.User.email",
  "entrypoint": "MyAppWeb.UserController.create/2",
  "sink": { "kind": "logger", "subtype": "Logger.info" },
  "boundary": "internal",
  "confidence": 0.82,
  "evidence": ["psn_014939e3417679ea", "psn_6f2bb5a9df3e"]
}
```

- Confidence rounding contract:
  - Clamp to `[0.0, 1.0]`
  - Serialize to fixed precision (assumption: 2 decimals) to minimize diff churn.

**Permissions Matrix**

| Role | Action | Allowed |
|---|---|---|
| Maintainer/CI actor with repository read/write | Run `mix priv_signal.infer` and write `privsignal.json` | Yes |
| Read-only contributor | Review flow output in PR diffs | Yes |
| External/LTI user roles | Trigger or modify inference | No (not applicable) |

## 10. Integrations & Platform Considerations
- N/A

## 12. Analytics & Success Metrics

**North Star / KPIs**

- `Flow Coverage`: % of runs where obvious PII+sink units produce at least one flow.
- `Determinism Pass Rate`: % of repeated-run comparisons with identical flow output (target >= 99.9%).
- `Reviewer Utility`: % of privacy-related PRs where reviewers reference flows during review (if tracked).

**Event Spec**

- Event: `priv_signal.infer.completed`
  - Properties: `repo`, `commit_sha`, `duration_ms`, `candidate_count`, `flow_count`, `error_count`, `determinism_check`.
  - Identifiers: repository + commit metadata only.
  - PII policy: no raw code snippets, no raw PII values, no user-content payload.
- Event: `priv_signal.infer.flow_emitted`
  - Properties: `flow_id`, `entrypoint_type`, `sink_kind`, `boundary`, `confidence_bucket`.

## 13. Risks & Mitigations

- False positives from coarse co-occurrence heuristics.
  - Mitigation: confidence scoring, explicit evidence, no enforcement in v1.
- False negatives where source/sink relation is real but not visible in same-unit context.
  - Mitigation: document scope limits; defer interprocedural analysis to future phase.
- Diff churn due to unstable ordering/rounding.
  - Mitigation: canonical ordering + fixed precision confidence serialization.
- Performance regressions in large modules.
  - Mitigation: grouped processing, benchmark gate in CI, telemetry thresholds.
- Developer mistrust of inferred semantics.
  - Mitigation: deterministic IDs, transparent evidence, explicit “Proto” framing.

## 14. Open Questions & Assumptions

**Assumptions**

- Phase 1 node inventory already tags sink kinds/subtypes and entrypoint context sufficiently for same-unit grouping.
- `mix priv_signal.infer` is the existing command path where flow inference should be integrated.
- Confidence precision of two decimals is acceptable for diff stability.
- Boundary classification can be decided from sink taxonomy without runtime destination lookup.

**Open Questions**

- Should a single unit emit multiple flows for multiple distinct source fields to one sink, or one aggregated flow per sink?
- What is the canonical tie-break ordering when confidence and entrypoint are identical (e.g., by `id` lexical)?
- Should there be a minimum confidence threshold for emission in v1, or emit all candidates?
- What exact benchmark corpus defines the p95 regression gate?
- Do downstream consumers require versioned artifact schema metadata (e.g., `schema_version` bump)?


## 16. QA Plan

**Automated**

- Unit tests:
  - Candidate inference rule behavior by node combinations.
  - Boundary mapping and confidence score/clamping.
  - Stable ID generation and canonical ordering.
- Property tests:
  - Determinism under reordered input nodes (same semantic set).
- Integration tests:
  - End-to-end `mix priv_signal.infer` writes `flows` with expected schema.
  - Backward compatibility for existing node-only consumers.
- Regression/perf tests:
  - Compare runtime against baseline on benchmark corpus.

## 17. Definition of Done

- [ ] PRD reviewed and accepted by product + engineering.
- [ ] `flows` schema contract finalized and documented.
- [ ] Inference engine implemented for same-unit rule set.
- [ ] Deterministic IDs and canonical ordering verified by tests.

