# FDD: Diff-Based Risk Scoring v2 (Node-Only)

## 1. Executive Summary
This design delivers a deterministic privacy risk scorer for CI/CD PR evaluation. The pipeline is explicitly staged: `scan` produces the candidate lockfile, `diff` produces semantic diff JSON, `score` consumes that diff JSON and emits deterministic score JSON, and optional `interpret` may add advisory commentary only. The primary affected users are developers, reviewers, privacy engineers, and CI maintainers who need repeatable risk outcomes with auditable reasoning. The implemented scope in this feature pack is Rubric V1 (flow-proxy signals from diff JSON), with node-native Rubric V2 explicitly deferred. The implementation removes legacy flow-config scoring and `PrivSignal.Risk.Assessor` usage from the score runtime path and introduces a dedicated `PrivSignal.Score.*` module family. OTP posture remains lightweight and robust: no long-lived stateful process is required for deterministic scoring, and each command run is isolated to a single invocation lifecycle. Runtime stability is achieved through strict score input contracts, deterministic sorting, and fail-closed behavior when required diff fields are missing. Performance posture targets CI ergonomics (p50 <= 1.5s, p95 <= 5s for score stage on 10k-node equivalent artifacts) with O(n) rule evaluation and bounded allocations. Observability is expanded via low-cardinality `:telemetry` events for run lifecycle, bucket outcomes, and rule hit counts. Security posture keeps the deterministic path local and non-networked, emits no runtime PII values, and treats advisory LLM calls as optional, rate-limited, and non-blocking. The highest risks are schema transition churn (flow-centric to node-centric diff), score calibration drift, and rollout confusion; these are mitigated through strict contracts, golden fixture calibration, and staged CI canary rollout with explicit rollback.

## 2. Requirements & Assumptions
### Functional Requirements
- `SCOR-FR-001` `mix priv_signal.score` accepts diff JSON input (`--diff <path>`) and emits score JSON output (`--output <path>`).
- `SCOR-FR-002` Deterministic scoring uses only semantic change entries from diff JSON; no LLM/network call in deterministic path.
- `SCOR-FR-003` Output label is one of `NONE | LOW | MEDIUM | HIGH`.
- `SCOR-FR-004` `NONE` is returned only when scoring-relevant semantic changes are absent.
- `SCOR-FR-005` Weighted-point rubric is default; thresholds and weights are config-driven and validated.
- `SCOR-FR-006` Boundary-tier escalation overlay can raise bucket regardless of additive score.
- `SCOR-FR-007` Advisory interpretation is optional and cannot mutate deterministic fields.
- `SCOR-FR-008` Output includes `score`, `points`, `summary`, `reasons`.
- `SCOR-FR-009` Score summary reports fixed deterministic counters for V1 (`nodes_added`, `external_nodes_added`, `high_sensitivity_changes`, `transforms_removed`, `new_external_domains`, `ignored_changes`, `relevant_changes`, `total_changes`).
- `SCOR-FR-010` Score input contract for this phase requires flow-proxy semantic diff list entries from diff JSON `version: v1` (`changes[]` with `type`, `flow_id`, `change`).
- `SCOR-FR-011` Scored items must carry normalized V1 fields when present: `type`, `flow_id`, `change`, `rule_id`, `severity`, `details`.
- `SCOR-FR-012` Missing required diff contract fields produce explicit non-zero failure; no LLM/flow-validation fallback.
- `SCOR-FR-013` Config supports `scoring.llm_interpretation.enabled` and model settings; default off.
- `SCOR-FR-014` Legacy flow-based score codepaths and config dependency are removed from score runtime.
- `SCOR-FR-015` CI orchestration order is fixed: `diff` before `score`, optional `interpret` after `score`.

### Non-Functional Requirements
- Determinism: byte-stable score JSON for identical diff input and config.
- Performance: score stage p50 <= 1.5s, p95 <= 5s, p99 <= 8s for large CI artifacts.
- Memory: score stage p95 <= 300MB.
- Reliability: >= 99.9% successful score runs excluding invalid artifact/setup.
- Observability: all score runs emit start/stop/error telemetry and per-rule hit counters.
- Security: deterministic score path has no external network dependency; no runtime PII values in output/telemetry.

### Explicit Assumptions
- `A1` Semantic diff JSON schema can be versioned to expose node/edge categories required by score.
Impact: requires coordinated change in `PrivSignal.Diff.*` output schema.
- `A2` Existing lockfile already contains enough node metadata to derive node/edge semantic changes.
Impact: if insufficient, schema evolution must happen before score rollout.
- `A3` CLI-only scope remains valid; no LiveView/HTTP integration in this phase.
Impact: simplifies OTP/process model and rollout.
- `A4` Legacy flow definitions in `priv-signal.yml` are allowed to exist transiently for other commands, but score command will not read or depend on them.
Impact: explicit decoupling avoids hidden behavior coupling during transition.
- `A5` Optional advisory interpretation remains non-gating and informational.
Impact: deterministic contract remains stable without model credentials.

## 3. Torus Context Summary
### What I know from current code/docs
- Score now lives in `lib/mix/tasks/priv_signal.score.ex` as deterministic diff-driven orchestration (`PrivSignal.Score.Input/Engine/Output`), with optional advisory via `PrivSignal.Score.Advisory`.
- Diff pipeline exists and is deterministic under `PrivSignal.Diff.*` with `Mix.Tasks.PrivSignal.Diff`.
- Diff today is flow-centric (`flow_added`, `flow_removed`, `flow_changed`) and `PrivSignal.Diff.Severity` is rule-based over flow changes.
- Runtime bootstrap is minimal (`PrivSignal.Runtime.ensure_started/0` starts telemetry/finch/req).
- Telemetry wrapper is thin (`PrivSignal.Telemetry.emit/3` -> `:telemetry.execute/3`).
- Config schema includes both `pii` and `flows` globally, and score loads config in `mode: :score` so `flows` are not required for scoring.
- Output writer currently writes `priv-signal.json` by default and logs telemetry in `PrivSignal.Output.Writer`.

### What I do not know yet
- Final node/edge diff JSON schema version and exact field naming for backward compatibility.
- Whether `mix priv_signal.diff` will produce the new node schema in-place (`v2`) or via new format flag.
- Whether `mix priv_signal.interpret` will be a new command immediately or follow-on implementation.

### Current runtime topology, boundaries, and tenancy
- Single CLI invocation, no persistent service state.
- Repo/workspace is the operational boundary.
- No multi-tenant runtime state or DB partitioning in current PrivSignal architecture.

## 4. Proposed Design
### 4.1 Component Roles & Interactions
- `Mix.Tasks.PrivSignal.Score` (rewrite):
  - Parse `--diff`, `--output`, optional `--format`, optional `--quiet`.
  - Load config once for scoring settings and advisory settings.
  - Validate score input contract.
  - Invoke deterministic engine.
  - Optionally invoke advisory interpretation.
  - Write score JSON artifact.
- `PrivSignal.Score.Input` (new):
  - `load_diff_json/1`, JSON parse, schema version guard, structural validation.
- `PrivSignal.Score.Engine` (new):
  - Applies rubric and escalation.
  - Produces `%ScoreReport{score, points, summary, reasons, metadata}`.
- `PrivSignal.Score.Rules` (new):
  - Maps normalized change records to weighted point contributions and rule IDs.
- `PrivSignal.Score.Buckets` (new):
  - Maps points and escalation state to final bucket.
- `PrivSignal.Score.Output.JSON` (new):
  - Stable rendering order and schema versioning for score artifact.
- `PrivSignal.Score.Advisory` (new, optional):
  - Accepts diff + score report; calls existing `PrivSignal.LLM.Client` when enabled.
  - Returns advisory payload or advisory error metadata without failing deterministic result.
- `PrivSignal.Score.Telemetry` (new helper or inline):
  - Centralized event emissions with low-cardinality metadata.

Interaction sequence:
1. CI executes `diff` and writes `tmp/privacy_diff.json`.
2. Score command reads diff JSON and validates required V1 change fields.
3. Engine computes deterministic score and reasons.
4. Output JSON is written to `tmp/priv_signal_score.json`.
5. Optional advisory runs after deterministic result exists and appends `llm_interpretation`.

### 4.2 State & Message Flow
- State ownership:
  - CLI process owns immutable parsed diff and scoring config.
  - Engine is pure functional; no shared mutable process state.
- Message flow:
  1. CLI parse -> config load -> diff parse.
  2. Normalize/sort changes -> rule evaluation reduce -> bucket selection.
  3. Render and write JSON -> optional advisory append/write.
- Backpressure points:
  - JSON parse for very large diff artifacts.
  - Optional advisory network call (isolated, timeout-bound).
- Determinism controls:
  - Stable sorting by deterministic key (`category`, `id`, `subtype`, `hash(details)`).
  - Numeric rounding for confidence deltas.
  - Explicit map/list ordering before encode.

### 4.3 Supervision & Lifecycle
- No long-lived worker tree required for deterministic scoring.
- Lifecycle per command:
  - `PrivSignal.Runtime.ensure_started/0`
  - deterministic compute
  - optional advisory request (synchronous, timeout-bounded in client config)
  - exit.
- Failure isolation:
  - Deterministic phase failures return non-zero immediately.
  - Advisory failures are captured and attached as metadata; command still exits success for deterministic output.

### 4.4 Alternatives Consdiered
- Alternative A: keep existing LLM-first score and “cross-check” with deterministic diff.
  - Rejected: ambiguity about source-of-truth and increased operational complexity.
- Alternative B: embed scoring directly inside `mix priv_signal.diff`.
  - Rejected: conflates responsibilities; PRD specifies explicit staged CI flow (`diff` then `score`).
- Alternative C: keep flow-centric scoring and map nodes back to flows.
  - Rejected: directly conflicts with node-only requirement and legacy removal.
- Recommended: dedicated node-only score command consuming diff JSON artifact.

### 4.5 Deterministic Scoring Rubric Definition
This section is normative for score v2. Deterministic score output must follow this rubric exactly unless overridden by validated config weights/thresholds.

Rubric precondition:
- Only node/edge changes related to declared PII metadata are scored.
- If there are zero scoring-relevant node/edge changes, output is `NONE` with `points = 0`.

Default weighted point assignments:

| Event | Points | Notes |
|---|---:|---|
| `edge_added` with internal boundary | +2 | New internal node-to-node transfer carrying PII |
| `edge_added` with external boundary | +5 | New boundary-crossing transfer |
| `node_added` sink `role.kind=http` and boundary `external` | +6 | New external HTTP/API sink |
| `node_added` sink `role.kind=telemetry` and boundary `external` | +5 | New external telemetry/analytics sink |
| `node_added` sink `role.kind=database_write` with `pii.sensitivity=high` | +5 | High-sensitivity persistence sink |
| `node_modified` sensitivity `low -> medium` | +2 | Sensitivity increase |
| `node_modified` sensitivity `medium -> high` | +4 | Sensitivity increase |
| `node_modified` transform removed (`redact`, `tokenize`, `hash`, `encrypt`) | +4 | Any protective transform removal |
| `node_added` or `node_modified` introduces new `pii.category` | +3 | Category absent in base and present in candidate |
| `edge_modified` widened PII field set | +2 | Additional PII fields on same transfer path |
| `node_removed` | +1 | Low default risk unless paired with transform removal event |
| `edge_removed` | +0 | Neutral by default |
| `node_modified` confidence increase only | +1 | Low informational risk |
| new external domain/vendor introduced | +4 | Domain not present in base artifact |

Default bucket thresholds:
- `NONE`: `points = 0` and no scoring-relevant node/edge changes.
- `LOW`: `points` in `[1, 3]`.
- `MEDIUM`: `points` in `[4, 8]`.
- `HIGH`: `points >= 9`.

Boundary-tier escalation overlay (bucket floor rules):
- Tier model:
  - Tier 0: internal in-memory only.
  - Tier 1: internal logging/storage.
  - Tier 2: external telemetry/analytics.
  - Tier 3: external third-party API/service.
- Escalation rules:
  - If any new Tier 3 transfer contains `pii.sensitivity=high`, final bucket is at least `HIGH`.
  - If any transfer moves from Tier `0|1` to Tier `2|3` with `pii.sensitivity=medium|high`, final bucket is at least `MEDIUM`.
  - If a new external domain/vendor is introduced with `pii.sensitivity=high`, final bucket is at least `HIGH`.

Final score algorithm:
1. Normalize and deterministically sort scoring-relevant changes.
2. Compute additive points from weighted events.
3. Map points to base bucket using thresholds.
4. Apply boundary-tier escalation floor rules.
5. Emit final `{score, points, summary, reasons}`.

Determinism and explainability constraints:
- Each applied rule must emit stable `rule_id` and `change_id`.
- `reasons` must be sorted deterministically (`severity_rank`, `rule_id`, `change_id`).
- Unknown event types are ignored for scoring and counted in `summary.ignored_changes`.
- Rubric overrides from config must be schema-validated (integer points, monotonic thresholds, no negative values).

Rubric v2 compatibility table (current implementation reality):

| Rule intent | v2 signal required (node/edge diff) | Current diff signal available | V1 status |
|---|---|---|---|
| HIGH: new external PII egress via HTTP sink | `nodes_added` with `node_type=sink`, `role.kind=http`, `boundary=external`, PII metadata | `flow_added` / `flow_changed.external_sink_added` with sink kind + boundary | Implementable via flow proxy |
| HIGH: new controller/liveview exposure node with PII | `nodes_added` with `node_type=entrypoint`, `entrypoint_context.kind=controller|liveview`, edge to PII sink/source | No explicit node-added diff category today | Blocked until node-diff schema |
| MEDIUM: new internal PII use (logging/db/telemetry) | `nodes_added` or `edges_added` internal with sink kind + PII metadata | `flow_added` internal and sink kind (partial) | Implementable (partial fidelity) |
| MEDIUM: PII category expansion | `nodes_modified` / `edges_modified` with added category | `flow_changed.pii_fields_expanded` | Implementable via flow proxy |
| LOW: changes to existing node/path without exposure expansion | `nodes_modified` / `edges_modified` non-escalating | `flow_changed` + optional confidence changed | Implementable via flow proxy |
| Vendor/domain introduction | `nodes_added|modified` with new external domain identity | Not first-class in current diff output | Blocked until node-diff schema |
| Transform removal escalation | `nodes_modified` showing transform removal on path | Not first-class in current diff output | Blocked until node-diff schema |

Implementation decision for this feature pack:
- Ship **Rubric V1 only** in this phase.
- Rubric V1 uses currently available semantic diff signals (flow-based proxy events) to produce deterministic `NONE|LOW|MEDIUM|HIGH`.
- Rubric V2 (true node/edge-native scoring) remains defined in this document but is deferred until diff schema exposes first-class node/edge categories and metadata.
- CI/docs must label V1 as deterministic and explainable, but “node-native fidelity” is an explicit follow-up deliverable.

## 5. Interfaces
### 5.1 HTTP/JSON APIs
- No HTTP endpoints; CLI JSON contracts only.
- CLI contracts:
  - `mix priv_signal.score --diff <path> [--output <path>] [--quiet]`
  - optional future: `mix priv_signal.interpret --diff <path> --score <path> [--output <path>]`
- Score input JSON (required shape, abbreviated):
```json
{
  "version": "v1",
  "metadata": {"base_ref": "origin/main"},
  "summary": {"high": 1, "medium": 0, "low": 0, "total": 1},
  "changes": [
    {
      "type": "flow_changed",
      "flow_id": "payments",
      "change": "external_sink_added",
      "severity": "high",
      "rule_id": "R-HIGH-EXTERNAL-SINK-ADDED",
      "details": {}
    }
  ]
}
```
- Score output JSON (required shape):
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
    "relevant_changes": 1,
    "total_changes": 1
  },
  "reasons": [
    {"rule_id": "R-HIGH-EXTERNAL-SINK-ADDED", "points": 6, "change_id": "flow:payments:external_sink_added"}
  ],
  "llm_interpretation": null
}
```
- Validation behavior:
  - missing diff file, malformed JSON, or missing required `changes[]` fields -> non-zero error.
  - unsupported diff schema version -> non-zero error with supported list.

### 5.2 LiveView
- Not applicable.

### 5.3 Processes
- Deterministic scoring runs in caller process.
- Optional advisory runs in command process with bounded timeout config.
- No Registry/GenStage/Broadway/PubSub needed.

## 6. Data Model & Storage
### 6.1 Ecto Schemas
- No Ecto/Postgres changes.
- New in-memory structs:
  - `PrivSignal.Score.Change`
  - `PrivSignal.Score.Reason`
  - `PrivSignal.Score.Report`
- Config schema updates (`PrivSignal.Config.Schema`):
  - Add `scoring` block:
    - `weights` map (positive integers)
    - `thresholds` (`low_max`, `medium_max`)
    - `boundary_tier_escalation` booleans/rules
    - `llm_interpretation.enabled` boolean default `false`
    - `llm_interpretation.model` string optional
  - Remove score-time dependency on `flows`.
- Migration plan (config contract):
  - score command no longer invokes `PrivSignal.Validate.run(config)` for flow validation.
  - score command fails only on scoring config or diff contract errors.

### 6.2 Query Performance
- No SQL query path.
- Expected algorithmic profile for score stage:
  - parse JSON: O(n)
  - normalize/sort: O(n log n)
  - scoring reduce: O(n)
  - render: O(n)
- For large artifacts, parsing and sorting dominate; avoid repeated traversals by precomputing normalized tuples.

## 7. Consistency & Transactions
- Consistency model: strong deterministic per-run.
- Idempotency:
  - same `diff.json` + same scoring config -> identical `score.json`.
- Transaction boundaries:
  - filesystem read of diff artifact
  - pure scoring computation
  - atomic file write of output (`File.write/3` to temp + rename recommended).
- Compensation:
  - if advisory append fails after deterministic write, keep deterministic artifact and emit advisory error metadata.

## 8. Caching Strategy
- Default: no cross-run cache.
- In-run memoization:
  - optional ETS for rule lookup tables only if profiling indicates benefit.
- `persistent_term` explicitly avoided for mutable scoring weights/rules to prevent global GC side effects.
- No multi-node cache coherence requirements.

## 9. Performance and Scalability Plan
### 9.1 Budgets
- Score stage latency:
  - p50 <= 1.5s
  - p95 <= 5s
  - p99 <= 8s
- Peak memory <= 300MB on target CI size.
- Advisory call budget:
  - timeout <= 8s
  - at most one retry.

### 9.2 Hotspots & Mitigations
- Hotspot: large diff JSON decode.
  - Mitigation: single decode pass, avoid re-encoding intermediate maps.
- Hotspot: sorting very large change lists.
  - Mitigation: sort once globally with tuple keys; avoid nested sort.
- Hotspot: rule evaluation branching cost.
  - Mitigation: pre-normalize event shape and use direct pattern-matching.
- Hotspot: advisory slow/down provider.
  - Mitigation: isolated timeout + non-fatal behavior.

## 10. Failure Modes & Resilience
- Diff file missing/unreadable -> explicit error, non-zero.
- Diff JSON malformed -> explicit parse error with path context.
- Missing required node/edge categories -> contract error, non-zero.
- Unknown diff schema version -> contract error, non-zero.
- Invalid scoring config (weights/thresholds) -> config error, non-zero.
- Advisory timeout/provider failure -> deterministic score remains, advisory annotated as unavailable.
- Output write failure -> non-zero with actionable filesystem error.

## 11. Observability
- New telemetry events:
  - `[:priv_signal, :score, :run, :start]`
  - `[:priv_signal, :score, :run, :stop]`
  - `[:priv_signal, :score, :run, :error]`
  - `[:priv_signal, :score, :rule_hit]`
  - `[:priv_signal, :score, :advisory, :start]`
  - `[:priv_signal, :score, :advisory, :stop]`
  - `[:priv_signal, :score, :advisory, :error]`
- Measurements:
  - `duration_ms`, `changes_total`, `points_total`, `rules_applied`, `error_count`.
- Metadata (low cardinality only):
  - `score_bucket`, `schema_version`, `advisory_enabled`, `ok`.
- Logging:
  - structured logs with run id, command stage, failure class.
  - no raw code diffs or high-cardinality identifiers in log metadata.
- Alerts (AppSignal):
  - score error rate > 2% over 15m.
  - score p95 > 5s over two windows.
  - `HIGH` bucket spike > 3x 7-day baseline.

## 12. Security & Privacy
- AuthN/AuthZ: local CLI execution only.
- Data minimization:
  - output and telemetry include symbolic node metadata only.
  - no runtime values, tokens, or user payloads.
- Least privilege:
  - deterministic score stage is filesystem read/write only.
  - advisory stage uses configured model key and is disabled by default.
- Tenant/repo isolation:
  - one repository per invocation, no shared mutable state.
- Auditability:
  - deterministic `reasons` with `rule_id` and `change_id` provide reproducible rationale.

## 13. Testing Strategy
- Unit tests:
  - contract parser validation for required node/edge categories.
  - rule evaluation for each event type and threshold boundary.
  - bucket resolution and escalation precedence.
- Property tests:
  - output determinism over reordered input changes.
  - idempotency over repeated runs.
- Integration tests:
  - CLI `score` happy path with fixture diff JSON.
  - failure cases: missing file, malformed JSON, schema mismatch.
  - advisory on/off behavior and non-mutation guarantee.
- Telemetry tests:
  - assert emitted events and metadata shape.
- Performance tests:
  - synthetic large diff fixtures to validate latency/memory budgets.

## 14. Backwards Compatibility
- Command surface compatibility:
  - `mix priv_signal.score` remains the entrypoint.
- Behavioral change:
  - `score` no longer consumes git patch or flow validation path.
- Removed compatibility:
  - flow-based scoring behavior is intentionally removed.
  - `PrivSignal.Risk.Assessor` no longer used by `score`.
- Transition guidance:
  - update CI to call `diff` first and pass `--diff` file to `score`.
  - keep `mix priv_signal.diff` output schema migration guide for one release.

## 15. Risks & Mitigations
- Risk: node/edge diff schema not ready for score contract.
  - Mitigation: ship schema v2 in diff first, then gate score rollout.
- Risk: calibration mismatch causes too many `HIGH` labels.
  - Mitigation: golden fixtures + canary repos + adjustable validated weights.
- Risk: users expect old score semantics.
  - Mitigation: release notes, command help update, explicit migration section in docs.
- Risk: advisory latency affects perceived command runtime.
  - Mitigation: deterministic write first; advisory optional with timeout and fail-open semantics.

## 16. Open Questions & Follow-ups
- Should advisory output be embedded in score JSON by default or written as separate artifact (`priv_signal_interpretation.json`)?
  - Suggested default: embed optional block in score JSON with `null` when disabled.
- Should diff schema v2 replace v1 directly or be selected via `--format-version v2`?
  - Suggested default: support both for one release, default to v2 in CI examples.
- Should score output include a deterministic hash of input diff artifact for traceability?
  - Suggested default: yes (`input_sha256`) in metadata.

## 17. References
- Task (Elixir docs) · https://hexdocs.pm/elixir/Task.html · Accessed 2026-02-15
- Task.Supervisor (Elixir docs) · https://hexdocs.pm/elixir/Task.Supervisor.html · Accessed 2026-02-15
- telemetry (HexDocs) · https://hexdocs.pm/telemetry/telemetry.html · Accessed 2026-02-15
- telemetry README (HexDocs) · https://hexdocs.pm/telemetry/readme.html · Accessed 2026-02-15
- ETS (Erlang/OTP docs) · https://www.erlang.org/doc/apps/stdlib/ets.html · Accessed 2026-02-15
- persistent_term (Erlang/OTP docs) · https://www.erlang.org/docs/21/man/persistent_term.html · Accessed 2026-02-15
- Jason (HexDocs) · https://hexdocs.pm/jason/Jason.html · Accessed 2026-02-15
