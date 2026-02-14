# Proto Flow Inference v1 (Single-Scope, Same-Unit) — FDD

## 1. Executive Summary
Proto Flow Inference v1 adds a deterministic flow-construction stage on top of the existing infer node inventory so reviewers can see likely PII movement in a single function/entrypoint scope. The feature affects maintainers and privacy reviewers using `mix priv_signal.scan` output in CI and PR diffs. The design keeps current scan and node production intact, then derives `flows` from canonical nodes in a pure, deterministic reducer step. This is intentionally local-only inference: no interprocedural traversal, no LLM, and no policy enforcement. OTP alignment remains command-scoped and failure-isolated by reusing bounded `Task.Supervisor.async_stream_nolink/6` in scan, while flow inference itself stays in-process and side-effect free. Determinism is enforced through canonical grouping keys, stable flow IDs, sorted evidence IDs, and fixed confidence rounding. Performance posture is low risk because flow derivation is O(n log n) over already-emitted nodes and does not reparse AST. Observability expands infer telemetry to include run start/stop, candidate counts, flow counts, and determinism signals suitable for AppSignal dashboards. The primary technical risks are diff churn from identity mistakes and confidence instability from heuristic drift; both are mitigated with explicit identity contracts, fixed score weights, and property tests.

## 2. Requirements & Assumptions
### Functional Requirements
- FR-001 to FR-003: infer same-unit candidates from node inventory using module+function context and entrypoint anchors where available.
- FR-004: emit flow fields `id`, `source`, `entrypoint`, `sink`, `boundary`, `confidence`, `evidence`.
- FR-005: generate deterministic flow IDs from semantic identity only.
- FR-006: compute deterministic additive confidence and clamp to `[0.0, 1.0]`.
- FR-007: classify boundary `internal|external` from sink taxonomy with `internal` default.
- FR-008 and FR-009: produce stable ordering and serialize under top-level `flows` without breaking existing node consumers.
- FR-010: evidence references node IDs only.
- FR-012: emit infer telemetry suitable for AppSignal monitoring.

### Non-Functional Requirements
- Performance: additional p95 overhead <= 10% vs current infer baseline, with p50 target <= 5%.
- Scalability: handle >= 5k nodes in < 3s for flow derivation on standard CI runner.
- Reliability: deterministic byte-stable output for unchanged inputs.
- Security/privacy: no runtime PII values in flows, logs, or telemetry metadata.
- Operability: feature flag controlled rollout with kill-switch.

### Explicit Assumptions
- A1: Current infer node schema (`schema_version` 1.1) is stable enough to serve as the sole input for Proto Flow v1.
Impact: if node contract changes, flow identity contract must version-lock against schema.
- A2: v1 sink coverage is primarily logger-derived nodes from current scanner output.
Impact: external boundary detection will initially be sparse and conservative.
- A3: Output artifact naming must preserve existing usage (`priv_signal.lockfile.json`) while introducing `flows` field.
Impact: PRD mention of `privsignal.json` requires compatibility mapping and docs clarity.
- A4: No DB persistence is introduced; flows are artifact-only.
Impact: no Ecto migration needed and no transactional DB concerns.

## 3. Torus Context Summary
### What I Know
- `Mix.Tasks.PrivSignal.Scan` orchestrates lockfile generation and writes JSON via `PrivSignal.Infer.Output.Writer` (`lib/mix/tasks/priv_signal.scan.ex`).
- `PrivSignal.Infer.Runner` currently calls `PrivSignal.Scan.Runner`, converts scan findings to canonical nodes via `PrivSignal.Infer.ScannerAdapter.Logging`, and emits envelope keys `schema_version/tool/git/summary/nodes/errors` (`lib/priv_signal/infer/runner.ex`).
- `PrivSignal.Scan.Runner` already provides bounded parallel file scanning via `Task.Supervisor.async_stream_nolink/6`, timeout handling, and scan telemetry (`lib/priv_signal/scan/runner.ex`).
- Deterministic node primitives exist: `NodeNormalizer`, `NodeIdentity`, `Contract.stable_sort_nodes` (`lib/priv_signal/infer/node_normalizer.ex`, `lib/priv_signal/infer/node_identity.ex`, `lib/priv_signal/infer/contract.ex`).
- Infer telemetry is currently minimal (`[:priv_signal, :infer, :output, :write]`) from writer only (`lib/priv_signal/infer/output/writer.ex`).
- Config already enforces `pii` plus user-defined `flows` and rejects deprecated `pii_modules` (`lib/priv_signal/config/schema.ex`).

### What I Don’t Know
- Whether artifact filename should migrate from `priv_signal.lockfile.json` to `privsignal.json` or support both indefinitely.
- Whether downstream consumers expect schema-version bump for adding top-level `flows`.
- Whether v1 should emit one flow per `(entrypoint,sink,source)` or aggregate multiple sources to one sink.
- Exact benchmark corpus and CI hardware profile for the p95 regression gate.

### Relevant Runtime Topology and Boundaries
- CLI-only, single-node execution model; no long-lived application process tree.
- Repository boundary acts as tenancy boundary in current PrivSignal architecture.
- Domain boundaries in this feature:
  - Scan domain (`PrivSignal.Scan.*`) discovers findings.
  - Infer domain (`PrivSignal.Infer.*`) normalizes nodes and will derive flows.
  - Output domain serializes stable contract for machine and human review.

## 4. Proposed Design
### 4.1 Component Roles & Interactions
- `PrivSignal.Infer.Runner` remains orchestrator and gains a second stage:
  - Stage A: existing findings -> nodes path.
  - Stage B: nodes -> proto flows path.
- New `PrivSignal.Infer.Flow` struct defines canonical flow payload.
- New `PrivSignal.Infer.FlowBuilder` performs same-unit grouping and candidate expansion.
- New `PrivSignal.Infer.FlowIdentity` derives deterministic `psf_*` IDs.
- New `PrivSignal.Infer.FlowScorer` applies additive weights and fixed rounding.
- `PrivSignal.Infer.Output.JSON` extends envelope with top-level `flows` while preserving existing keys.
- `PrivSignal.Infer.Contract` adds flow contract validation and stable sort functions.

Interaction sequence:
1. Scan runner returns findings.
2. Logging adapter maps findings to normalized nodes.
3. Nodes are stably sorted.
4. Flow builder groups nodes by same-unit context and emits candidates.
5. Flow scorer computes confidence/boundary/evidence normalization.
6. Flow identity generates deterministic IDs.
7. Writer emits JSON with both `nodes` and `flows`.

### 4.2 State & Message Flow
- State ownership:
  - Scan worker state remains per-task in `Scan.Runner`.
  - Flow derivation uses immutable in-memory node list owned by infer caller process.
- Message flow:
  - No new OTP message bus required; flow derivation is pure function pipeline.
- Backpressure points:
  - Existing scan concurrency caps and timeouts remain primary throttle.
  - Flow stage avoids per-node process fan-out to prevent mailbox growth and scheduling overhead.

### 4.3 Supervision & Lifecycle
- No new long-lived process is introduced.
- Existing temporary `Task.Supervisor` in scan stage remains unchanged.
- Flow stage failures are isolated as infer-stage failures and return actionable error context.
- Strict mode behavior remains consistent: any scan errors fail run; flow derivation errors always fail run because output would be contract-invalid.

### 4.4 Alternatives Considered
- Alternative A: Build flows directly from scan findings, bypassing node layer.
Why rejected: duplicates normalization logic, weakens evidence stability, and ties flows to scanner-specific findings.
- Alternative B: Per-file flow inference during scan workers.
Why rejected: complicates deterministic global ordering and makes cross-node same-unit assembly brittle when scanner sources expand.
- Alternative C: Add GenServer cache for flow candidates.
Why rejected: CLI workload is short-lived and pure reduction is simpler, safer, and easier to test.
- Recommended: infer flows from canonical nodes in a deterministic reducer after scan completion.

## 5. Interfaces
### 5.1 HTTP/JSON APIs
- No HTTP endpoint changes.
- Infer artifact contract extends to:
  - top-level `flows: [flow]`.
  - backward-compatible retention of existing top-level keys and `nodes`.
- Flow JSON shape:
```json
{
  "id": "psf_9c31a7e2b0ad",
  "source": "MyApp.User.email",
  "entrypoint": "MyAppWeb.UserController.create/2",
  "sink": {"kind": "logger", "subtype": "Logger.info"},
  "boundary": "internal",
  "confidence": 0.82,
  "evidence": ["psn_014939e3417679ea", "psn_6f2bb5a9df3e"]
}
```
- Validation:
  - `confidence` numeric in `[0.0,1.0]`.
  - `evidence` non-empty list of existing node IDs.
  - `boundary` enum `internal|external`.

### 5.2 LiveView
- No LiveView runtime in PrivSignal.
- LiveView-related requirement is represented as entrypoint classification from node context and naming heuristics only.

### 5.3 Processes
- Existing process model retained:
  - caller process + temporary task supervisor for scan workers.
- No Registry/GenStage/Broadway needed in v1.

## 6. Data Model & Storage
### 6.1 Ecto Schemas
- No Ecto schema changes and no DB migrations in v1.
- New in-memory structs:
  - `%PrivSignal.Infer.Flow{}` with fields `id, source, entrypoint, sink, boundary, confidence, evidence`.
  - `%PrivSignal.Infer.FlowCandidate{}` optional private struct for scoring pipeline.
- Contract/versioning:
  - bump infer artifact schema from `1.1` to `1.2` when adding top-level `flows`.
  - keep `nodes` unchanged for backward compatibility.

### 6.2 Query Performance
- No SQL path.
- Flow derivation complexity:
  - grouping key build: O(n)
  - candidate expansion and sort: O(n log n)
  - memory: O(n) for grouped node references.
- Representative grouping key:
  - `{module, function, file_path}` from normalized `code_context`.

## 7. Consistency & Transactions
- Consistency model: deterministic strong consistency per run.
- Transaction boundaries:
  - config load/validate -> scan -> node normalization -> flow derivation -> artifact write.
- Idempotency:
  - same config + same code + same env toggles => byte-identical flows.
- Deterministic identity tuple for `psf_*`:
  - `{source_ref, entrypoint, sink.kind, sink.subtype, boundary}`.
- Evidence consistency:
  - evidence IDs are sorted lexicographically and deduped before serialization.

## 8. Caching Strategy
- Default: no persistent cache.
- Optional in-run memoization:
  - map of grouped nodes by key to avoid repeated scans in scoring.
- Do not use `persistent_term` for per-run changing flow state.
- Multi-node coherence not applicable in current CLI topology.

## 9. Performance and Scalability Plan
### 9.1 Budgets
- Infer total p50 <= 5s, p95 <= 20s for large repos (existing enhanced-scan target).
- Incremental flow-stage overhead: p50 <= 250ms, p95 <= 1.5s at 5k nodes.
- Memory delta for flow stage <= 150 MB.
- Max per-run emitted flows guardrail: 50k with warning log and telemetry flag.

### 9.2 Hotspots & Mitigations
- Hotspot: high node cardinality in large modules.
Mitigation: grouped reduction and single-pass candidate generation.
- Hotspot: candidate explosion when multiple sources and sinks co-occur.
Mitigation: dedupe by semantic key and cap duplicate evidence per flow.
- Hotspot: diff churn from floating-point noise.
Mitigation: fixed scoring weights + fixed precision rounding (2 decimals).

## 10. Failure Modes & Resilience
- Node contract drift:
  - behavior: flow builder returns explicit contract error.
  - mitigation: schema gating in `Infer.Contract` and regression tests.
- Missing code context on nodes:
  - behavior: node excluded from flow grouping, counted in telemetry as `node_context_missing`.
- Write failure:
  - behavior: infer command exits non-zero and leaves previous file untouched if atomic write strategy is enabled.
- Timeout/parse failures in scan:
  - behavior: existing strict/non-strict semantics unchanged.

Retry/backoff:
- No retries for deterministic transform failures.
- Keep scan retry policy unchanged.

## 11. Observability
### Telemetry Events
- `[:priv_signal, :infer, :run, :start]`
- `[:priv_signal, :infer, :flow, :build]`
- `[:priv_signal, :infer, :run, :stop]`
- Existing: `[:priv_signal, :infer, :output, :write]`

### Measurements
- `duration_ms`, `node_count`, `candidate_count`, `flow_count`, `error_count`, `determinism_hash_changed`.

### Metadata
- `schema_version`, `strict_mode`, `ok`, `entrypoint_kinds_present`, `boundary_counts`.

### Cardinality Guardrails
- Do not emit module names, function names, flow IDs, or node IDs as telemetry tags.
- Keep detailed evidence in artifact only.

### AppSignal Alerts
- infer error rate > 2% over 15m.
- infer p95 duration regression > 10% against 7-day baseline.
- `determinism_hash_changed` > 0 for repeated-run control job.

## 12. Security & Privacy
- AuthN/AuthZ: local CLI actor only; no remote invocation surface.
- Tenant isolation: repository is hard boundary; do not mix data across repos/jobs.
- PII handling:
  - flows include symbolic references only (`Module.field`), never runtime values.
  - telemetry/logs redact payload-level identifiers and evidence details.
- Auditability:
  - deterministic IDs + evidence node IDs provide traceable review chain.

## 13. Testing Strategy
- Unit tests:
  - `FlowBuilder` same-unit grouping and anchor rule behavior.
  - `FlowScorer` additive scoring, clamping, rounding.
  - `FlowIdentity` determinism under input reordering.
- Property tests:
  - shuffled node input yields identical sorted flow output.
- Integration tests:
  - `PrivSignal.Infer.Runner` emits `flows` plus existing `nodes` envelope.
  - strict/non-strict behavior unchanged.
  - output JSON remains backward-compatible for node consumers.
- Resilience tests:
  - malformed node context handling.
  - evidence dedupe and missing-node-reference rejection.
- Performance tests:
  - benchmark fixture at 5k+ nodes to verify p95 overhead target.

## 15. Risks & Mitigations
- Risk: over-inference in large mixed handlers.
Mitigation: keep same-unit boundary strict and conservative boundary classification.
- Risk: under-inference due to missing source nodes.
Mitigation: allow inferred source fallback (`PII touched`) with lower confidence.
- Risk: downstream consumer breakage on schema extension.
Mitigation: schema version bump + compatibility tests + rollout flag.
- Risk: telemetry cardinality explosion.
Mitigation: metadata allowlist and explicit ban on IDs/paths in tags.

## 16. Open Questions & Follow-ups
- Should output filename remain `priv_signal.lockfile.json` in v1, or add optional canonical alias `privsignal.json`?
Suggested default: keep current filename and add docs note that PRD artifact naming maps to infer JSON output.
- Should one sink with many source refs emit many flows or one aggregated flow?
Suggested default: emit one flow per source reference to maximize diff precision.
- Should emission threshold suppress very low-confidence candidates?
Suggested default: no threshold in v1; emit all candidates with confidence.
- Should we include deterministic artifact hash in summary for drift monitoring?
Suggested default: yes, add summary field `flows_hash` computed from canonical serialized flows.

## 17. References
- Elixir `Task.Supervisor` docs · https://hexdocs.pm/elixir/Task.Supervisor.html · Accessed February 8, 2026
- Elixir `Task` docs (`async_stream`) · https://hexdocs.pm/elixir/Task.html#async_stream/3 · Accessed February 8, 2026
- Erlang/OTP Supervisor Principles · https://www.erlang.org/doc/system/sup_princ.html · Accessed February 8, 2026
- Erlang/OTP ETS docs · https://www.erlang.org/doc/apps/stdlib/ets.html · Accessed February 8, 2026
- Elixir `persistent_term` docs · https://www.erlang.org/doc/apps/erts/persistent_term.html · Accessed February 8, 2026
- Telemetry docs (`:telemetry.execute/3`) · https://hexdocs.pm/telemetry/telemetry.html · Accessed February 8, 2026
- OpenTelemetry Elixir instrumentation · https://opentelemetry.io/docs/languages/erlang/instrumentation/ · Accessed February 8, 2026
- AppSignal Elixir integration docs · https://docs.appsignal.com/elixir/instrumentation/integrating-appsignal.html · Accessed February 8, 2026
- Ecto migrations and indexes (`Ecto.Migration`) · https://hexdocs.pm/ecto_sql/Ecto.Migration.html · Accessed February 8, 2026
- Ecto constraints and upserts (`Ecto.Repo`) · https://hexdocs.pm/ecto/Ecto.Repo.html · Accessed February 8, 2026
- Phoenix LiveView docs (`handle_event/3`) · https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#c:handle_event/3 · Accessed February 8, 2026
