# PrivSignal PII Scanning Expansion (Proto-Flow-Ready Inventory) — PRD

## 1. Overview

**Feature Name**

PrivSignal PII Scanning Expansion (Proto-Flow-Ready Inventory)

**Summary**

PrivSignal will evolve from a logging-only PII detector into a deterministic PII node inventory generator that captures reusable, structured touchpoints across the codebase. The feature will emit normalized JSON nodes with stable identity, contextual metadata, and evidence so downstream Proto Flow inference can consume the output without re-analyzing raw findings. This phase intentionally excludes edge inference and policy enforcement.

**Links**

- Issue/Epic: `docs/features/enhanced_scan/informal.md`
- Related docs: `docs/prd.md`, `docs/fdd.md`, `docs/plan.md`
- Command surface: `mix priv_signal.infer`

## 2. Background & Problem Statement

Current behavior is limited to AST-based logging checks that detect some PII usage but produce scanner-specific findings instead of reusable graph-ready artifacts. Findings are not normalized as deterministic, semantically stable nodes and do not include enough structural context for downstream inference.

Affected users are privacy engineers, application developers, and CI owners who need repeatable, reviewable inventory artifacts for risk analysis and future flow modeling.

This work is needed now because Proto Flow inference depends on a high-quality inventory layer; without it, inference would be brittle, incomplete, or forced to repeatedly process low-level AST findings.

## 3. Goals & Non-Goals

**Goals**

- Expand scanner architecture from one-off logging findings to a general node inventory model.
- Produce deterministic JSON output where identical code inputs always yield identical node IDs/order/content.
- Refactor existing logging detection to emit `sink` nodes with complete context.
- Add entrypoint/module-role classification scaffolding (controller/liveview/job/background worker) with confidence/evidence.
- Keep the inventory inference-agnostic so future flow inference can build on it without redesign.
- Enable lockfile-style artifact generation suitable for code review and CI diffs.

**Non-Goals**

- Inferring edges or end-to-end data flows.
- Interprocedural taint analysis or whole-program dataflow.
- Policy enforcement, CI failure gating, or auto-remediation.
- Human-friendly narrative explanations or PR comment generation.
- Implementing all future scanners (HTTP/DB/telemetry/files) in this phase.

## 4. Users & Use Cases

**Primary Users / Roles**

- Privacy engineer: validates PII touchpoint coverage and readiness for flow inference.
- Application engineer: reviews inventory diffs when code changes touch PII-related logic.
- Platform/CI owner: consumes deterministic artifacts in automated pipelines.

**Use Cases / Scenarios**

- A developer runs `mix priv_signal.infer` locally and receives a deterministic inventory JSON that includes logging sink nodes and inferred entrypoint context.
- A pull request changes logging statements containing `user.email`; CI output shows stable node IDs and evidence changes, enabling targeted review.
- A privacy engineer compares inventory artifacts across commits to identify new/removed touchpoints without re-running custom analysis scripts.

## 5. UX / UI Requirements

**Key Screens/States**

- CLI success state: command exits `0` and writes inventory artifact.
- CLI validation error state: deterministic, actionable error output when files cannot be parsed or config is invalid.
- CI artifact state: generated inventory file can be attached, diffed, and versioned.

**Navigation & Entry Points**

- Primary entry point: `mix priv_signal.infer`.
- Secondary: downstream CI workflows that invoke the command and publish artifacts.

**Accessibility**

- WCAG 2.1 AA applies to any generated web/report surfaces; for this CLI phase, output must be screen-reader friendly (plain text + machine-readable JSON).
- Keyboard-only operation is fully supported (CLI only).
- Any future rendered report must preserve focus order, alt-text for non-text assets, and minimum contrast ratios.

**Internationalization**

- CLI and JSON keys remain English and stable for machine consumption.
- Human-readable strings should be externalizable in future UI layers; this phase introduces no locale-formatted dates/numbers in artifact identity fields.
- JSON content must remain locale-independent.

**Screenshots/Mocks**

- No screenshots provided.

## 6. Functional Requirements

| ID | Description | Priority (P0/P1/P2) | Owner |
|---|---|---|---|
| FR-001 | Refactor existing logging PII scanner to emit normalized `sink` nodes instead of ad-hoc findings. | P0 | Engineering |
| FR-002 | Define and enforce canonical node schema with fields: `id`, `node_type`, `pii`, `code_context`, `role`, `evidence`, `confidence`. | P0 | Engineering |
| FR-003 | Generate deterministic node IDs from semantic identity fields only (excluding line numbers and run-specific metadata). | P0 | Engineering |
| FR-004 | Normalize file paths to repository-relative, POSIX-style paths in output. | P0 | Engineering |
| FR-005 | Canonicalize module/function identity (`Module.Name`, `function/arity`) and include it in `code_context`. | P0 | Engineering |
| FR-006 | Sort emitted nodes deterministically (primary: `id`; secondary: canonical tuple) before writing JSON artifact. | P0 | Engineering |
| FR-007 | Capture PII metadata per node: reference/field, category, sensitivity. | P0 | Engineering |
| FR-008 | Capture role-specific metadata for `sink` nodes (`logger`, `http`, `telemetry`, `file`), with this phase implementing `logger` detection. | P0 | Engineering |
| FR-009 | Add module classification scaffolding for `entrypoint` context (`controller`, `liveview`, `job`, `worker`) with confidence score and evidence signals when heuristic. | P1 | Engineering |
| FR-010 | Emit evidence list for each node with AST-derived references (line, expression kind, matching rule). | P0 | Engineering |
| FR-011 | Integrate inventory generation into `mix priv_signal.infer` artifact pipeline. | P0 | Engineering |
| FR-012 | Ensure generated inventory is treated as machine-managed output (no manual edits required). | P1 | Engineering/DevEx |
| FR-013 | Add schema/version field to artifact for forward-compatible scanner expansion. | P1 | Engineering |
| FR-014 | Preserve inference agnosticism by omitting node edges/flow links in output. | P0 | Engineering |

## 7. Acceptance Criteria (Testable)

- **AC-001 (FR-001, FR-011)**  
  Given a project containing logging statements with known PII fields  
  When `mix priv_signal.infer` runs successfully  
  Then output includes `sink` nodes representing those logging touchpoints in the inventory artifact.

- **AC-002 (FR-002, FR-007, FR-010)**  
  Given a detected PII touchpoint  
  When a node is serialized  
  Then it includes required schema fields and contains `pii` metadata plus at least one evidence item.

- **AC-003 (FR-003, FR-006)**  
  Given unchanged code and configuration  
  When inventory generation runs on different machines or repeated runs  
  Then node IDs and serialized node ordering are byte-for-byte identical.

- **AC-004 (FR-004)**  
  Given source files under nested directories  
  When nodes are emitted  
  Then `code_context.file_path` is repo-relative and uses normalized separators.

- **AC-005 (FR-005)**  
  Given nodes from modules with named functions  
  When output is generated  
  Then each applicable node includes canonical module and `function/arity` identifiers.

- **AC-006 (FR-008, FR-014)**  
  Given logging-derived findings  
  When nodes are generated  
  Then role metadata identifies `sink.kind=logger` and output contains no flow edges.

- **AC-007 (FR-009)**  
  Given a module matching controller or LiveView heuristics  
  When entrypoint classification is attached  
  Then the node includes classification label, confidence score, and evidence signals.

- **AC-008 (FR-013)**  
  Given a valid artifact  
  When parsed by downstream tooling  
  Then schema version is present and validates against documented contract.

- **AC-009 (FR-012)**  
  Given generated inventory checked into source control  
  When developers rerun infer without code changes  
  Then no manual post-processing is required and diffs are empty.

## 8. Non-Functional Requirements

**Performance & Scale**

- `mix priv_signal.infer` inventory phase p50 <= 5s and p95 <= 20s for repositories up to 5,000 Elixir source files on CI-standard runners.
- Memory target: <= 700 MB RSS p95 during scan on above workload.
- Throughput target: process >= 250 files/second p50 for parseable Elixir modules.
- Output writing must stream or batch safely to avoid quadratic behavior on large node sets.

**Reliability**

- Scanner completes with partial-failure accounting: unparsable files are logged as structured warnings; successful files still produce artifact.
- Command exits non-zero only for fatal configuration/runtime failures.
- Retry behavior for transient file read errors: up to 2 retries with bounded backoff.

**Security & Privacy**

- Output must not include raw runtime PII values; only code references/identifiers.
- Artifact must include no secrets, credentials, or environment variable values.
- Access to artifacts follows existing repo/CI permissions; no cross-tenant data mixing.
- Abuse protection: cap maximum evidence payload size per node.

**Compliance**

- Generated artifacts must be auditable and attributable to commit SHA + scanner version.
- Accessibility requirements apply to any future UI/report consumer; this phase remains CLI/JSON.
- Data retention follows existing CI artifact retention policy; no new persistence store introduced.

**Observability**

- Emit AppSignal metrics/events for: scan start/end, files scanned, nodes emitted by type, parser failures, deterministic hash of output.
- Add dashboard panels for duration, failure rate, and node count drift.
- Add alert: scan fatal error rate > 2% over 1 hour in CI.

## 9. Data Model & APIs

**Ecto Schemas & Migrations**

- No Postgres schema changes in this phase.
- Inventory is file artifact output; DB persistence is explicitly out of scope.

**Context Boundaries**

- Update scanning/inference pipeline modules under `PrivSignal` scanner/infer contexts.
- Keep node schema/serialization isolated from detector-specific logic to support future scanners.
- Retain clear boundary: detectors produce candidate observations; normalizer produces canonical nodes.

**APIs / Contracts**

- CLI contract: `mix priv_signal.infer` writes inventory artifact as part of infer output.
- Artifact contract sketch:

```json
{
  "schema_version": "1.1",
  "generated_at": "2026-02-07T20:14:12Z",
  "tool": { "name": "priv_signal", "version": "0.3.0" },
  "project": { "app": "my_app", "root": "." },

  "nodes": [
    {
      "id": "psn_01c4f4c1c0b6",
      "type": "sink",
      "kind": "logger",
      "sink": { "provider": "Logger", "call": "Logger.info/1" },

      "pii": [
        {
          "ref": "Oli.Accounts.User.email",
          "field": "email",
          "category": "contact",
          "sensitivity": "medium"
        }
      ],

      "context": {
        "file": "lib/my_app/accounts/user_service.ex",
        "module": "MyApp.Accounts.UserService",
        "function": "create_user/1"
      },

      "evidence": [
        { "file": "lib/my_app/accounts/user_service.ex", "line": 118, "excerpt": "Logger.info(\"created user\", email: user.email)" }
      ],

      "confidence": 1.0
    },

    {
      "id": "psn_6f2bb5a9df3e",
      "type": "entrypoint",
      "kind": "controller",
      "entrypoint": { "module_kind": "controller" },

      "context": {
        "file": "lib/my_app_web/controllers/user_controller.ex",
        "module": "MyAppWeb.UserController",
        "function": "create/2"
      },

      "evidence": [
        { "file": "lib/my_app_web/controllers/user_controller.ex", "line": 1, "signal": "use MyAppWeb, :controller" },
        { "file": "lib/my_app_web/controllers/user_controller.ex", "line": 12, "signal": "defines create/2" }
      ],

      "confidence": 0.98
    },

    {
      "id": "psn_1f9a0ef2d0a7",
      "type": "sink",
      "kind": "http",
      "sink": { "provider": "Finch", "call": "Finch.request/3", "destination_hint": "api.segment.io" },

      "pii": [
        {
          "ref": "Oli.Accounts.User.phone",
          "field": "phone",
          "category": "contact",
          "sensitivity": "medium"
        }
      ],

      "context": {
        "file": "lib/my_app/analytics/segment.ex",
        "module": "MyApp.Analytics.Segment",
        "function": "track_signup/1"
      },

      "evidence": [
        { "file": "lib/my_app/analytics/segment.ex", "line": 44, "excerpt": "Finch.request(req, MyFinch, [])" },
        { "file": "lib/my_app/analytics/segment.ex", "line": 39, "excerpt": "payload = %{phone: user.phone, ...}" }
      ],

      "confidence": 0.75
    },

    {
      "id": "psn_8a3a4f8dc2fd",
      "type": "transform",
      "kind": "redact",
      "transform": { "name": "redact", "call_hint": "MyApp.PII.redact/1" },

      "pii": [
        {
          "ref": "Oli.Accounts.User.email",
          "field": "email",
          "category": "contact",
          "sensitivity": "medium"
        }
      ],

      "context": {
        "file": "lib/my_app/pii.ex",
        "module": "MyApp.PII",
        "function": "safe_log_user/1"
      },

      "evidence": [
        { "file": "lib/my_app/pii.ex", "line": 22, "excerpt": "email = redact(user.email)" }
      ],

      "confidence": 0.9
    }
  ]
}

```

- Stability rules:
- Identity hash inputs include node type + canonical module/function + normalized path + normalized PII reference + role kind.
- Identity hash inputs exclude line numbers, timestamps, and run environment.

**Permissions Matrix**

| Role | Action | Allowed |
|---|---|---|
| Developer | Run `mix priv_signal.infer` locally | Yes |
| CI service account | Generate inventory artifact on build | Yes |
| Developer | Manually edit generated inventory as source of truth | Discouraged (generated) |
| Privacy engineer | Review and diff inventory artifacts | Yes |

## 10. Integrations & Platform Considerations

**GenAI (if applicable)**

- Not applicable for this phase; no model calls required.

**Caching/Perf**

- Optional parse cache may be used if already present; cache key must include file content hash and scanner version.
- Cache invalidation must occur on file content change or schema version bump.
- N+1 concerns are minimal (file-based static analysis), but repeated AST traversals should be consolidated per file.

**Multi-Tenancy**
- N/A

## 11. Feature Flagging, Rollout & Migration
- N/A


## 12. Analytics & Success Metrics

**North Star / KPIs**

- Determinism KPI: >= 99.9% repeated-run hash match for unchanged commit inputs.
- Coverage KPI: 100% of existing logging PII findings represented as valid nodes.
- Stability KPI: < 1% unexpected node churn (excluding code changes) across daily CI runs.

**Event Spec**

- `priv_signal.inventory.run_started`
- `priv_signal.inventory.run_completed`
- `priv_signal.inventory.run_failed`
- `priv_signal.inventory.nodes_emitted`

Event properties:

- `repo`, `commit_sha`, `scanner_version`, `schema_version`
- `duration_ms`, `files_scanned`, `nodes_total`, `nodes_by_type`
- `parse_failures_count`, `determinism_hash`

PII policy:

- Events must never include raw PII values or source code snippets containing sensitive literals.

## 13. Risks & Mitigations

- Risk: unstable IDs due to hidden non-semantic fields.  
  Mitigation: formalize identity inputs, property tests for determinism across randomized file ordering.

- Risk: false-positive/false-negative classification in heuristic entrypoint tagging.  
  Mitigation: include confidence/evidence, keep classification additive and non-blocking.

- Risk: large repositories causing performance regressions.  
  Mitigation: benchmark gates, single-pass AST traversal where possible, progressive optimization.

- Risk: downstream coupling to pre-release schema.  
  Mitigation: explicit versioning, changelog, compatibility window.

- Risk: artifact bloat from excessive evidence payloads.  
  Mitigation: evidence cap per node and concise structured fields.

## 14. Open Questions & Assumptions

**Assumptions**

- Existing logging scanner accuracy is sufficient as baseline for migration to node output.
- Inventory artifacts are generated in CI and may be checked in as lockfile-like outputs.
- LTI and multi-tenant runtime boundaries are not directly modified by this CLI-scanner phase.
- No database persistence is required for node inventory in this phase.

**Open Questions**

- Should `generated_at` be excluded from lockfile variants to avoid non-semantic diffs, or should lockfile omit runtime metadata entirely?
- What exact repository path should store generated inventory artifact(s) by default?
- What is the final canonical taxonomy for `pii.category` and `sensitivity` levels?
- Should heuristic entrypoint classification be emitted on all nodes or only on `entrypoint` nodes?
- What compatibility policy is required for schema evolution beyond one minor version?

## 16. QA Plan

**Automated**

- Unit tests for canonicalization, ID generation, role mapping, and evidence normalization.
- Property tests for deterministic output under shuffled file traversal and repeated runs.
- Integration tests for `mix priv_signal.infer` artifact generation.


## 17. Definition of Done

- [ ] PRD approved and committed at `docs/features/enhanced_scan/prd.md`
- [ ] Logging scanner emits canonical `sink` nodes
- [ ] Deterministic ID generation and stable sorting implemented and tested
- [ ] `mix priv_signal.infer` emits versioned inventory artifact
- [ ] Telemetry events, AppSignal dashboards, and alerts are live
- [ ] Feature flag `enhanced_pii_inventory` wired with environment defaults
- [ ] QA automated and manual checks completed
- [ ] Rollout and rollback runbooks documented
- [ ] Open questions resolved or explicitly deferred with owners
