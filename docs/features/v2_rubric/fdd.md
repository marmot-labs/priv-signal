# FDD: Rubric V2 (Categorical, Non-Numeric)

## 1. Executive Summary
Rubric V2 replaces additive points with a categorical, event-presence decision model for `mix priv_signal.score`. The feature affects developers, reviewers, and privacy/security engineers who consume CI risk outputs and need faster, more explainable decisions. The design keeps the existing staged pipeline (`scan -> diff -> score`) and upgrades the diff/score contract so score classification is direct and deterministic. The scoring decision order is strict: empty diff yields `NONE`; otherwise any `HIGH` event yields `HIGH`; otherwise any `MEDIUM` event yields `MEDIUM`; otherwise `LOW`. To support this, semantic diff must emit node/edge-native events with normalized category fields and stable event ids. Score output removes numeric fields and emits only categorical result, deterministic reasons, and category/event summaries. OTP posture stays lightweight and robust: command-scoped processing, immutable normalized input, no long-lived stateful scorer process, and explicit failure boundaries at artifact parsing and contract validation. Performance posture is O(n) over event lists with stable sorting, single-pass summary aggregation, and bounded memory per invocation. The highest risks are event taxonomy ambiguity and downstream contract migration; mitigation is strict contracts and hard-cutover tests. This design is an intentional breaking change that removes legacy scoring codepaths and artifacts rather than preserving compatibility.

## 2. Requirements & Assumptions
### Functional Requirements
- `RV2-FR-001` `mix priv_signal.score` must consume semantic diff JSON and produce score values only from `NONE|LOW|MEDIUM|HIGH`.
- `RV2-FR-002` If the semantic diff is empty, score must be `NONE`.
- `RV2-FR-003` If any `HIGH` event exists, score must be `HIGH`.
- `RV2-FR-004` If no `HIGH` exists and any `MEDIUM` event exists, score must be `MEDIUM`.
- `RV2-FR-005` If semantic diff is non-empty and no `HIGH`/`MEDIUM` events exist, score must be `LOW`.
- `RV2-FR-006` Output must include deterministic `reasons` with stable event/rule identifiers.
- `RV2-FR-007` Score output must not include `points`.
- `RV2-FR-008` Diff output must include node/edge-native events with boundary, destination/vendor identity, sensitivity, pii-category delta, and transform-change metadata.
- `RV2-FR-009` Diff output must include stable `event_id` values for deterministic reason reporting.
- `RV2-FR-010` Repeated runs on identical inputs must produce byte-stable JSON ordering.

### Non-Functional Requirements
- Determinism: byte-stable score output for identical diff/config input.
- Performance: score stage p50 <= 1.0s, p95 <= 3.0s, p99 <= 5.0s on CI-class artifacts.
- Memory: score stage p95 <= 200MB.
- Reliability: >= 99.9% successful score runs excluding invalid artifacts/config.
- Security/privacy: no runtime PII values in logs/output; only symbolic metadata.

### Explicit Assumptions
- `A1` Infer artifact `schema_version 1.2` fields (`nodes`, `flows`, `entrypoint_context`, `role`, `pii`) are sufficient to build node/edge-native diff events.
Impact: if vendor identity or transform metadata is missing, scanners/infer must enrich before full-fidelity HIGH/MEDIUM mapping.
- `A2` Existing flow identifiers remain stable enough to support deterministic event correlation.
Impact: unstable IDs increase false add/remove event rates; mitigation is stronger identity keys in diff normalization.
- `A3` CLI remains single-tenant per repo invocation with no shared runtime state.
Impact: caching/coherence design remains local and simple.
- `A4` Rubric V2 is the only supported scoring approach once released in this repo.
Impact: implementation must delete legacy score code/config paths in the same delivery.
- `A5` Advisory LLM output remains optional and non-gating.
Impact: deterministic output remains local and network-independent.

## 3. PrivSignal Context Summary
### What I know from docs/code reconnaissance
- Score runtime is deterministic and v2 event-based (`lib/priv_signal/score/engine.ex`, `lib/priv_signal/score/rubric_v2.ex`, `lib/priv_signal/score/output/json.ex`).
- Diff runtime emits `version: v2` event-centric semantic changes (`lib/priv_signal/diff/semantic_v2.ex`, `lib/priv_signal/diff/render/json.ex`).
- Infer lockfile contract already includes `nodes` and `flows` in `schema_version 1.2` (`lib/priv_signal/infer/contract.ex`, `lib/priv_signal/infer/output/json.ex`).
- Runtime startup is command-scoped (`lib/priv_signal/runtime.ex`).
- Config validation supports scoring blocks and allows score-mode loading without mandatory `flows` (`lib/priv_signal/config/schema.ex`, `lib/priv_signal/config/loader.ex`).
- Existing feature docs show established patterns for deterministic contracts and CI-first design (`docs/features/scoring/*`, `docs/features/semantic_diff/fdd.md`).

### What I do not know yet
- Final canonical taxonomy names for all V2 event types.
- Whether existing scanners already capture transform removal and third-party vendor identity with enough precision.
- Whether any internal scripts in this repo still parse legacy score fields and need coordinated update in the same PR.

### Runtime topology and boundaries
- Single Mix task process per command invocation.
- No database persistence, no multi-node runtime cluster, no LiveView/HTTP runtime for this feature.
- Operational boundary is the checked-out repository and generated JSON artifacts.

## 4. Proposed Design
### 4.1 Component Roles & Interactions
- `PrivSignal.Diff.SemanticV2` (new): builds node/edge-native semantic events from normalized base/candidate artifacts.
- `PrivSignal.Diff.Render.JSON` (update): emits `version: "v2"` and `events` array with stable fields and deterministic order.
- `PrivSignal.Score.Input` (update): accepts diff `version: "v2"` contract with strict event validation.
- `PrivSignal.Score.RubricV2` (new): classifies each event into `high|medium|low` trigger classes and maps to rule ids.
- `PrivSignal.Score.Engine` (update): categorical decision engine; additive points path is removed.
- `PrivSignal.Score.Output.JSON` (update): emits `version: "v2"`, `score`, `reasons`, `summary`, `llm_interpretation`; omits `points`.
- `PrivSignal.Config.Schema` and `PrivSignal.Config` (update): remove legacy scoring keys no longer used by score runtime.
- `Mix.Tasks.PrivSignal.Score` (update): enforces v2-only input contract with explicit unsupported-contract errors.

Interaction flow:
1. `diff` loads base/candidate artifacts and computes deterministic node/edge semantic events.
2. `diff` writes `version: "v2"` diff JSON with normalized event fields and event ids.
3. `score` validates v2 event contract and classifies events via rubric v2.
4. `score` chooses final category using strict decision order.
5. `score` writes categorical output with deterministic reasons and summaries.

### 4.2 State & Message Flow
- State ownership:
  - Task process owns parsed config and diff event list.
  - Event classification is pure function over immutable event data.
- Message flow:
  - Input parse -> normalize -> classify events -> aggregate summary -> choose bucket -> render output.
- Backpressure points:
  - Large JSON parse and event normalization.
  - Optional advisory network call, isolated from deterministic path.
- Mailbox/bottleneck posture:
  - No central long-lived GenServer hot path.
  - Keep computation in bounded synchronous reductions to avoid unbounded mailbox growth.

### 4.3 Supervision & Lifecycle
- No new long-lived worker required for deterministic scoring.
- Continue command-scoped lifecycle:
  - `PrivSignal.Runtime.ensure_started/0`
  - run deterministic diff/score stages
  - optional advisory call
  - clean exit.
- Failure isolation:
  - Contract failures are fail-closed with non-zero exit.
  - Advisory failures remain non-fatal and do not mutate deterministic fields.

### 4.4 Alternatives Considered
- Alternative A: keep point-based engine and derive categories from thresholds.
Rejected: violates PRD intent to remove numeric model and makes reasoning indirect.
- Alternative B: classify directly from flow-proxy events without diff schema changes.
Rejected: cannot reliably represent required V2 cases (controller/liveview entrypoint emergence, transform removal, vendor identity changes).
- Alternative C: perform event classification inside `diff` and emit final score there.
Rejected: couples concerns and reduces independent testability of scoring.
- Recommended: versioned diff v2 event contract plus categorical score engine.

## 5. Interfaces
### 5.1 HTTP/JSON APIs
- No HTTP routes are added.
- CLI contracts:
  - `mix priv_signal.diff --base <ref> --format json --output <path>`
  - `mix priv_signal.score --diff <path> --output <path>`
- Diff JSON v2 shape (abbreviated):
```json
{
  "version": "v2",
  "metadata": {
    "base_ref": "origin/main",
    "schema_version_base": "1.2",
    "schema_version_candidate": "1.2"
  },
  "summary": {
    "events_total": 3,
    "events_high": 1,
    "events_medium": 1,
    "events_low": 1
  },
  "events": [
    {
      "event_id": "evt:node_added:controller:new:abc123",
      "event_type": "node_added",
      "event_class": "high",
      "rule_id": "R2-HIGH-NEW-EXTERNAL-PII-EGRESS",
      "node_id": "node_123",
      "edge_id": null,
      "entrypoint_kind": "controller",
      "boundary_before": "internal",
      "boundary_after": "external",
      "sensitivity_before": "medium",
      "sensitivity_after": "high",
      "destination": {"kind": "http", "vendor": "stripe", "domain": "api.stripe.com"},
      "pii_delta": {"added_categories": ["financial"], "added_fields": ["ssn"]},
      "transform_delta": {"removed": ["tokenize"], "added": []}
    }
  ]
}
```
- Score JSON v2 shape (abbreviated):
```json
{
  "version": "v2",
  "score": "HIGH",
  "reasons": [
    {"event_id": "evt:node_added:controller:new:abc123", "rule_id": "R2-HIGH-NEW-EXTERNAL-PII-EGRESS"}
  ],
  "summary": {
    "events_total": 3,
    "events_high": 1,
    "events_medium": 1,
    "events_low": 1
  },
  "llm_interpretation": null
}
```
- Rate limits: not applicable for deterministic local path.

### 5.2 LiveView
- Not applicable for current CLI-only runtime.
- If future LiveView UI is added, consume score artifacts read-only and preserve deterministic fields.

### 5.3 Processes
- Deterministic path remains process-local with pure reductions.
- Optional future optimization:
  - `Task.Supervisor.async_stream_nolink/6` for event normalization chunks when event volume is high.
  - bounded concurrency (`max_concurrency = System.schedulers_online()`).
- No Registry/GenStage/Broadway required for current scope.

## 6. Data Model & Storage
### 6.1 Ecto Schemas
- No Ecto schemas or DB migrations required.
- Storage is artifact-only JSON in workspace output paths.
- Schema evolution plan:
  - Introduce diff `version: "v2"` as the required score input.
  - Introduce score `version: "v2"` and remove `points` from v2 output.
  - Keep deterministic key ordering and explicit required fields.
- Indexes:
  - Not applicable (no database).
  - In-memory indexing by `event_id`, `node_id`, and optional `edge_id` maps for O(1) lookups during aggregation.

### 6.2 Query Performance
- No SQL path.
- Expected plans:
  - Parse JSON O(n).
  - Classify events O(n).
  - Deterministic sort O(n log n) over event/reason arrays.
- Performance-sensitive keys:
  - `event_class`, `event_type`, and `rule_id` used in single-pass reductions to avoid repeated scans.

## 7. Consistency & Transactions
- Consistency model: strong per-run deterministic consistency.
- Transaction boundaries:
  - Whole-run atomicity for output write: write only after full validation and classification succeeds.
- Idempotency:
  - identical diff artifact + config -> byte-identical score artifact.
- Retriable flows:
  - deterministic path retry-safe.
  - advisory network path retry bounded by configured retries and timeout.
- Compensation:
  - on failure, return a clear error and do not write partial score files.

## 8. Caching Strategy
- Default: no cross-run cache.
- In-run cache:
  - normalized event maps and rule lookups in local maps.
- Avoid `persistent_term` for this feature because update costs can trigger global GC and the workload is short-lived CLI.
- ETS not required initially; introduce only if profiling shows repeated expensive normalization with high event cardinality.
- Multi-node coherence is not applicable for current CLI topology.

## 9. Performance and Scalability Plan
### 9.1 Budgets
- Score runtime:
  - p50 <= 1.0s
  - p95 <= 3.0s
  - p99 <= 5.0s
- Allocation targets:
  - <= 30MB transient allocations per 10k events in scoring stage.
- Repo pool sizing:
  - not applicable (no DB Repo dependency).
- ETS ceiling:
  - not applicable unless optional ETS cache is introduced.

### 9.2 Hotspots & Mitigations
- Hotspot: large event arrays from broad code changes.
Mitigation: stream decode if needed, chunk normalize, one-pass classify/aggregate.
- Hotspot: repeated nested map access for event metadata.
Mitigation: normalize once into compact structs/maps with required keys.
- Hotspot: reason ordering cost at high cardinality.
Mitigation: deterministic sort on small reason subset (only triggering classes) when possible.

## 10. Failure Modes & Resilience
- Unsupported diff version -> explicit contract error with supported version list.
- Missing required event fields -> fail-closed contract error.
- Taxonomy mismatch (unknown `event_type` or `event_class`) -> count in `summary.unknown_events`; default classification is `LOW` only if event is valid but unmapped.
- Invalid category ordering or malformed reasons -> fail output render.
- Advisory timeout/failure -> preserve deterministic score output and report advisory failure in command output.
- Graceful shutdown:
  - no persistent workers; command exits cleanly on SIGTERM after current operation boundary.

## 11. Operational Diagnostics
- Logging:
  - structured log lines for score decision and contract errors.
  - redact all raw pii field values when present.
- Validation focus:
  - use deterministic fixture outputs and test failures as the primary operational signal for correctness.

## 12. Security & Privacy
- AuthN/AuthZ:
  - local CLI only; no external service dependency for deterministic scoring.
- Tenant isolation:
  - per-repo invocation; no shared mutable state across tenants.
- PII handling:
  - only category/sensitivity metadata allowed in outputs and logs.
  - never emit runtime payload values or request bodies.
- Least privilege:
  - read artifacts and write output path only.
- Auditability:
  - include `version` and deterministic reasons for traceable review.

## 13. Testing Strategy
- Unit tests:
  - rubric v2 classifier per rule mapping (HIGH/MEDIUM/LOW).
  - decision-order tests (`HIGH` precedence over `MEDIUM`, etc.).
  - contract validation tests for diff v2 required fields.
- Property tests:
  - permutation invariance for event ordering.
  - stable output hash for repeated runs.
- Integration tests:
  - `diff` v2 + `score` v2 end-to-end with fixtures.
  - explicit rejection tests for legacy score contracts/inputs.
  - advisory on/off and failure modes.
- Failure injection:
  - malformed JSON, unknown event classes, missing metadata, advisory timeouts.
- Performance tests:
  - synthetic artifacts with >= 10k events.
  - validate latency and memory budgets.

## 14. Cutover Strategy
- This feature is a hard cutover to v2 scoring contracts and behavior.
- Remove legacy point-based score runtime modules and legacy score config handling from the score path.
- Require diff `version: "v2"` for score execution.
- `points` is removed from score output and must not be emitted.
- Legacy v1 score artifacts are unsupported after cutover and should fail with explicit contract errors.

## 15. Risks & Mitigations
- Risk: event taxonomy under-specification causes inconsistent classification.
Mitigation: publish canonical rule catalog and fixture-backed contract tests before rollout.
- Risk: missing infer metadata for vendor/transform deltas reduces HIGH fidelity.
Mitigation: add explicit infer enrichment tasks and mark unsupported detections with explicit warnings.
- Risk: downstream tooling expects `points`.
Mitigation: update in-repo consumers in the same change and add explicit tests that `points` is absent.
- Risk: performance regression on large diffs.
Mitigation: one-pass reductions, bounded sorts, performance gate in CI.

## 16. Open Questions & Follow-ups
- OQ-001 Should `LOW` include unknown but valid event types, or should unknown types fail-closed in strict mode by default?
Suggested default: warn and count unknown in non-strict mode, fail in strict mode.
- OQ-002 Is vendor/domain identity always available from current scanners for HTTP/analytics sinks?
Suggested default: optional field with explicit `unknown_vendor` marker and follow-up scanner enrichment.
- OQ-003 Should score v2 include both triggering and non-triggering reasons?
Suggested default: include triggering reasons only for concise explainability, keep full event counts in summary.

## 17. References
- Elixir `GenServer` docs · https://hexdocs.pm/elixir/GenServer.html · Accessed 2026-02-15
- Elixir `Task.Supervisor` docs · https://hexdocs.pm/elixir/Task.Supervisor.html · Accessed 2026-02-15
- Erlang/OTP `persistent_term` docs · https://www.erlang.org/doc/apps/erts/persistent_term.html · Accessed 2026-02-15
- Erlang/OTP `ets` docs · https://www.erlang.org/doc/apps/stdlib/ets.html · Accessed 2026-02-15
- Phoenix PubSub docs · https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html · Accessed 2026-02-15
- Ecto `Ecto.Multi` docs · https://hexdocs.pm/ecto/Ecto.Multi.html · Accessed 2026-02-15

## 18. Implementation Evidence (2026-02-15)
- Phase 1 (Diff v2 contract): `test/priv_signal/diff/semantic_v2_test.exs`, `test/priv_signal/diff/render_json_v2_test.exs`, `test/priv_signal/diff/event_id_determinism_test.exs`, `test/mix/tasks/priv_signal_diff_v2_integration_test.exs`
- Phase 2 (Score v2 IO cutover): `test/priv_signal/score/input_v2_test.exs`, `test/priv_signal/score/output_json_v2_test.exs`, `test/mix/tasks/priv_signal_score_v2_contract_test.exs`, `test/priv_signal/config_schema_score_legacy_rejection_test.exs`
- Phase 3 (Rubric v2 engine): `test/priv_signal/score/rubric_v2_rules_test.exs`, `test/priv_signal/score/engine_v2_test.exs`, `test/priv_signal/score/decision_order_v2_test.exs`, `test/priv_signal/score/determinism_v2_property_test.exs`
- Phase 4 (Security + legacy removal): `test/priv_signal/score/security_redaction_v2_test.exs`, `test/priv_signal/score/legacy_contract_rejection_test.exs`
- Phase 5 (E2E + perf + quality gates): `test/mix/tasks/priv_signal_v2_e2e_test.exs`, `test/priv_signal/score/perf_v2_baseline_test.exs`, `mix test`, `mix compile --warnings-as-errors`, `mix format --check-formatted`

## 19. Appendix: FR Traceability (Phase 0 Freeze)
| FR-ID | Requirement (Short) | Primary Modules | Planned Tests |
|---|---|---|---|
| RV2-FR-001 | Score consumes semantic diff and emits valid category | `lib/priv_signal/score/input.ex`, `lib/priv_signal/score/engine.ex`, `lib/mix/tasks/priv_signal.score.ex` | `test/priv_signal/score/contract_v2_test.exs`, `test/mix/tasks/priv_signal_score_v2_contract_test.exs` |
| RV2-FR-002 | Empty diff -> `NONE` | `lib/priv_signal/score/engine.ex` | `test/priv_signal/score/contract_v2_test.exs`, `test/priv_signal/score/decision_order_v2_test.exs` |
| RV2-FR-003 | Any HIGH event -> `HIGH` | `lib/priv_signal/score/rubric_v2.ex`, `lib/priv_signal/score/engine.ex` | `test/priv_signal/score/rubric_v2_rules_test.exs`, `test/priv_signal/score/decision_order_v2_test.exs` |
| RV2-FR-004 | No HIGH + any MEDIUM -> `MEDIUM` | `lib/priv_signal/score/rubric_v2.ex`, `lib/priv_signal/score/engine.ex` | `test/priv_signal/score/rubric_v2_rules_test.exs`, `test/priv_signal/score/decision_order_v2_test.exs` |
| RV2-FR-005 | Non-empty without HIGH/MEDIUM -> `LOW` | `lib/priv_signal/score/rubric_v2.ex`, `lib/priv_signal/score/engine.ex` | `test/priv_signal/score/engine_v2_test.exs`, `test/priv_signal/score/decision_order_v2_test.exs` |
| RV2-FR-006 | Deterministic reasons | `lib/priv_signal/score/engine.ex`, `lib/priv_signal/score/output/json.ex` | `test/priv_signal/score/contract_v2_test.exs`, `test/priv_signal/score/determinism_v2_property_test.exs` |
| RV2-FR-007 | No `points` in score v2 output | `lib/priv_signal/score/output/json.ex`, `lib/mix/tasks/priv_signal.score.ex` | `test/priv_signal/score/contract_v2_test.exs`, `test/priv_signal/score/output_json_v2_test.exs` |
| RV2-FR-008 | Diff emits node/edge-native metadata | `lib/priv_signal/diff/semantic_v2.ex`, `lib/priv_signal/diff/render/json.ex` | `test/priv_signal/diff/contract_v2_test.exs`, `test/priv_signal/diff/semantic_v2_test.exs` |
| RV2-FR-009 | Stable `event_id` semantics | `lib/priv_signal/diff/semantic_v2.ex` | `test/priv_signal/diff/contract_v2_test.exs`, `test/priv_signal/diff/event_id_determinism_test.exs` |
| RV2-FR-010 | Byte-stable repeated runs | `lib/priv_signal/diff/render/json.ex`, `lib/priv_signal/score/output/json.ex` | `test/priv_signal/diff/contract_v2_test.exs`, `test/priv_signal/score/determinism_v2_property_test.exs` |

## 20. Appendix: Frozen V2 Event Taxonomy and Rule Catalog
Event classes:
- `high`
- `medium`
- `low`

Canonical `event_type` values for Rubric V2:
- `node_added`
- `node_removed`
- `node_updated`
- `edge_added`
- `edge_removed`
- `edge_updated`
- `boundary_changed`
- `sensitivity_changed`
- `destination_changed`
- `transform_changed`

Rule catalog:
- `R2-HIGH-NEW-EXTERNAL-PII-EGRESS`
- `R2-HIGH-EXTERNAL-HIGH-SENSITIVITY-EXPOSURE`
- `R2-HIGH-EXTERNAL-TRANSFORM-REMOVED`
- `R2-HIGH-NEW-VENDOR-HIGH-SENSITIVITY`
- `R2-MEDIUM-NEW-INTERNAL-SINK`
- `R2-MEDIUM-SENSITIVITY-INCREASE-ON-EXISTING-PATH`
- `R2-MEDIUM-BOUNDARY-TIER-INCREASE`
- `R2-MEDIUM-CONFIDENCE-AND-EXPOSURE-INCREASE`
- `R2-LOW-PRIVACY-RELEVANT-RESIDUAL-CHANGE`

Policy notes:
- `event_class` is assigned by rubric mapping logic, not trusted from raw scanner input.
- Unknown valid `event_type` is warning-only in non-strict mode and fail-closed in strict mode.
- Unknown `event_class` is always a contract error.

## 21. Appendix: Deterministic Ordering Keys (Frozen)
`events[]` order:
1. `event_class` rank: `high`, `medium`, `low`, then unknown
2. `event_type` (ascending lexical)
3. `event_id` (ascending lexical)
4. `node_id` (ascending lexical; empty string when missing)
5. `edge_id` (ascending lexical; empty string when missing)
6. stable canonical JSON key order of `details` (tie-breaker)

`reasons[]` order:
1. `rule_id` (ascending lexical)
2. `event_id` (ascending lexical)

Determinism guarantees:
- For identical normalized diff input and config, rendered JSON is byte-stable.
- Ordering is independent of source map/list insertion order.

## 22. Appendix: Supported Score Input Matrix (Frozen)
| Diff `version` | Required top-level field | Accepted by `mix priv_signal.score` | Expected behavior |
|---|---|---|---|
| `v2` | `events` (list) | Yes | Parse, validate, classify, and render score v2 output |
| `v1` | `changes` (list) | No | Fail with unsupported-contract error |
| missing | n/a | No | Fail with missing required field error |
| unknown (`v3`, etc.) | n/a | No | Fail with unsupported-contract error |

Required v2 event fields:
- `event_id` (string, non-empty)
- `event_type` (string, in frozen taxonomy)
- `node_id` or `edge_id` (at least one present)

Optional v2 event fields:
- `rule_id` (string; may be populated after classification)
- `destination`, `pii_delta`, `transform_delta` (object metadata)
