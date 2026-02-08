## 1. Executive Summary
The Semantic Diff Engine introduces a new CLI command, `mix priv_signal.diff`, that explains privacy-relevant changes between lockfile artifacts in terms reviewers can act on quickly. It primarily affects developers, privacy reviewers, and CI maintainers who currently rely on noisy line diffs. The design intentionally keeps `diff` analysis-only: it does not invoke `infer` and does not mutate artifacts. Input mode is hybrid for CI robustness: base lockfile is loaded from a git ref, while candidate defaults to the checked-out workspace file with an optional candidate-ref override. The implementation reuses existing PrivSignal patterns: Mix-task orchestration, deterministic reducers, schema contracts, and low-overhead `:telemetry` events. Semantic change detection is rule-driven and deterministic, with explicit categories (`flow_added`, `flow_removed`, `flow_changed`, optional `confidence_changed`) and advisory severity (`high|medium|low`). The pipeline is CPU/memory bounded and single-run scoped, with no long-lived process state and no database coupling. Performance posture targets CI ergonomics (p50 <= 1s, p95 <= 3s for target artifact sizes) by normalizing once and diffing with indexed maps. Primary risks are schema drift, false-positive churn from insufficient normalization, and ambiguity around optional artifacts; mitigation includes strict contract checks, stable sort/identity invariants, and clear strict/warn modes. Observability adds diff-specific events and AppSignal-aligned measurements while guarding cardinality. Rollout is controlled via a feature flag and canary cohorts with kill-switch fallback.

Spec Alignment Note (2026-02-08): PRD and FDD are aligned on hybrid diff input mode and required diff telemetry coverage.

## 2. Requirements & Assumptions
### Functional Requirements
- FR-001: Add `mix priv_signal.diff` hybrid inputs: required `--base <ref>` plus candidate from workspace by default, with optional `--candidate-ref <ref>`.
- FR-002: Normalize artifacts so formatting/order/irrelevant metadata do not produce diffs.
- FR-003: Detect `flow_added` and `flow_removed`.
- FR-004: Detect `flow_changed` subtypes (`external_sink_added_removed`, `pii_fields_expanded_reduced`, `boundary_changed`).
- FR-005: Apply deterministic severity rules with stable `rule_id` attribution.
- FR-006: Render default human output grouped by severity.
- FR-007: Render machine JSON output with stable schema and metadata.
- FR-008: Optionally include confidence transitions behind explicit opt-in.
- FR-009: Use deterministic exit codes; no hidden fallback behavior.
- FR-010: Include provenance metadata (base ref, candidate source descriptor, artifact schema versions, generation time).
- FR-011: Emit telemetry for start/stop/errors and change distributions.
- FR-012: Maintain compatibility with current infer artifact schema(s).
- FR-013: `diff` compares committed lockfiles only and must not execute inference.

### Non-Functional Requirements
- Runtime: p50 <= 1.0s, p95 <= 3.0s for <= 500 flows and <= 5,000 field references.
- Memory: p95 <= 250MB for target dataset.
- Reliability: >= 99.5% successful runs excluding invalid inputs.
- Determinism: repeated runs over identical base/candidate inputs yield byte-stable JSON output and stable severity.
- Security: no secret leakage; no raw runtime PII values in logs/telemetry.

### Explicit Assumptions
- A1: Lockfile path is stable and known (`priv-signal-infer.json` default), with optional override.
Impact: nonstandard repos should use `--artifact-path` or config fallback.
- A2: `flow.id` is stable enough across compared artifacts to anchor changed-vs-added/removed logic.
Impact: if IDs churn, diff quality degrades; we need identity fallback matching.
- A3: Optional scanner/confidence fields may be missing and should be warning-only by default.
Impact: strict mode must be explicit to avoid CI breakage surprises.
- A4: CLI-only runtime (no LiveView/HTTP) remains true for this phase.
Impact: interface surface is simpler and test matrix remains narrow.
- A5: Observability requirements are fully aligned across PRD and FDD; diff telemetry is required for rollout safety.
Impact: implementation can proceed without spec conflict.

## 3. Torus Context Summary
### What I Know
- PrivSignal is a Mix-task CLI with command entrypoints in `lib/mix/tasks/*`.
- `mix priv_signal.infer` already emits deterministic lockfile JSON (`priv-signal-infer.json`) with `nodes` and `flows` via `PrivSignal.Infer.Runner` and `PrivSignal.Infer.Output.JSON`.
- Scan/infer pipeline already uses bounded `Task.Supervisor.async_stream_nolink` patterns for failure isolation and backpressure in file analysis.
- Current telemetry wrapper is a thin `PrivSignal.Telemetry.emit/3` over `:telemetry.execute/3`.
- There is existing git command plumbing (`PrivSignal.Git.Options`, `PrivSignal.Git.Diff`) and a small diff utility (`PrivSignal.Diff.Hunks`).
- No Ecto/Postgres persistence is currently involved in infer/scan artifacts.

### What I Don’t Know
- Whether lockfile path should be configurable in this feature’s first release.
- Whether confidence metadata is guaranteed present in all supported artifact schema versions.
- Whether output should include a strict machine schema version policy (semver vs major-only).
- Desired default behavior when optional scanner sections are absent (warn vs strict-fail).

### Runtime Topology / Tenancy
- Single process tree per CLI invocation.
- Repo boundary is operational tenancy boundary.
- No cross-repo state sharing and no multi-node coherence requirements in v1.

## 4. Proposed Design
### 4.1 Component Roles & Interactions
- `Mix.Tasks.PrivSignal.Diff` (new): CLI parsing, runtime bootstrap, orchestration, exit codes.
- `PrivSignal.Diff.Runner` (new): end-to-end pipeline coordinator.
- `PrivSignal.Diff.ArtifactLoader` (new): load base lockfile from git ref (`git show <base_ref>:<path>`) and candidate lockfile from workspace by default; optional candidate-ref mode (`git show <candidate_ref>:<path>`).
- `PrivSignal.Diff.Normalize` (new): canonicalization (sorted lists, compact maps, metadata stripping, normalized enums).
- `PrivSignal.Diff.Semantic` (new): computes semantic changes.
- `PrivSignal.Diff.Severity` (new): deterministic rule engine + `rule_id`.
- `PrivSignal.Diff.Render.Human` and `PrivSignal.Diff.Render.JSON` (new): output layers.
- `PrivSignal.Diff.Contract` (new): JSON schema/version checks and supported adapter logic.

Interaction sequence:
1. Parse args and resolve base ref, candidate source mode, and options.
2. Load base lockfile from git ref and candidate lockfile from workspace (or candidate ref when provided).
3. Validate/normalize artifacts.
4. Compute semantic changes.
5. Apply severity rules and build summary.
6. Emit requested format (human/json), telemetry, and deterministic exit code.

### 4.2 State & Message Flow
- State ownership is run-local and immutable after normalization.
- Suggested in-memory shapes:
  - `%DiffContext{base_ref, candidate_source, options}`
  - `%NormalizedArtifact{flows_by_id, pii_index, scanner_index, schema_version}`
  - `%SemanticChange{id, type, flow_id, change, severity, rule_id, details}`
  - `%DiffReport{metadata, summary, changes}`
- Message flow is synchronous by default; optional bounded tasks can load artifacts in parallel only when candidate-ref mode is used.
- Backpressure points:
  - git subprocess calls (base always, candidate optional)
  - JSON decode/normalize (O(n log n) due to sorting)

### 4.3 Supervision & Lifecycle
- No long-lived GenServer required.
- Command process lifecycle:
  - `PrivSignal.Runtime.ensure_started/0`
  - optionally start temporary `Task.Supervisor` for two parallel artifact loads
  - execute diff pipeline
  - terminate cleanly.
- Failure isolation:
  - Parse/contract failures return typed errors; no partial writes.
  - Timeout on git read/parse results in non-zero exit with actionable remediation.

### 4.4 Alternatives Considered
- Alternative A: run `infer` inside `diff` and compare inferred candidate state.
Rejected: violates PRD/Workflow Fit contract, introduces hidden side effects and runtime variability.
- Alternative B: generic JSON structural diff with post-hoc filtering.
Rejected: too noisy and brittle for semantic categories.
- Alternative C: persist diff runs in DB for analytics-first architecture.
Rejected: unnecessary operational coupling for CLI-first feature.
- Chosen: deterministic lockfile-to-lockfile semantic compare with hybrid loading (base ref + workspace candidate default) and explicit category rules.

## 5. Interfaces
### 5.1 HTTP/JSON APIs
- No HTTP API changes.
- CLI contract:
  - `mix priv_signal.diff --base <ref> [--candidate-ref <ref>] [--candidate-path <path>] [--format human|json] [--include-confidence] [--strict] [--artifact-path <path>] [--output <path>]`
- Exit codes:
  - `0`: successful run (changes or no-change)
  - `2`: invalid arguments/refs/artifact not found
  - `3`: parse/contract/unsupported schema failure
  - `4`: internal execution failure

#### Example command executions
- Local branch, default candidate from workspace file:
  - `mix priv_signal.diff --base origin/main`
- Local branch with explicit candidate workspace file:
  - `mix priv_signal.diff --base origin/main --candidate-path priv-signal-infer.json`
- CI PR pipeline (base from target branch ref, candidate from checked-out PR workspace):
  - `git fetch origin main --depth=1`
  - `mix priv_signal.diff --base origin/main --format json --output tmp/priv-signal-diff.json`
- Ref-to-ref comparison (both artifacts loaded from git objects, no workspace dependency):
  - `mix priv_signal.diff --base origin/main --candidate-ref HEAD`
- Nonstandard lockfile path:
  - `mix priv_signal.diff --base origin/main --artifact-path artifacts/privacy/priv-signal-infer.json`

### 5.2 LiveView
- Not applicable (CLI-only feature).

### 5.3 Processes
- Default: single-process pure pipeline.
- Optional optimization: `Task.async_stream` with `max_concurrency: 2` for base/candidate loads only in candidate-ref mode.
- No Registry, GenStage, Broadway, or PubSub required for v1.

## 6. Data Model & Storage
### 6.1 Ecto Schemas
- No Ecto schema or DB migrations required.
- New internal structs/modules only under `PrivSignal.Diff.*`.
- Artifact compatibility:
  - Require top-level `schema_version`, `flows` list.
  - Adapter layer supports known infer schema versions (current and one previous major/minor as configured).

### 6.2 Query Performance
- No SQL path.
- Core operations:
  - Build `flows_by_id` map: O(n)
  - Per-flow comparison: O(n)
  - Stable output sorting: O(k log k), where `k` is number of changes
- Memory profile: dominated by two decoded artifacts plus normalized indices.

Representative compare algorithm:
1. `added = candidate_ids - base_ids`
2. `removed = base_ids - candidate_ids`
3. `shared = intersection(base_ids, candidate_ids)`
4. For each shared ID, run semantic subtype checks in fixed order and emit zero-to-many changes.

## 7. Consistency & Transactions
- Consistency model: strong per-run deterministic consistency.
- No distributed transactions and no persistence writes.
- Idempotency: identical base ref + candidate source/options produce identical JSON bytes and summary counts.
- Partial failure policy: fail fast before rendering if either artifact cannot be validated.

## 8. Caching Strategy
- v1 default: no cross-run cache.
- In-run memoization only (maps for flow lookup and normalized field sets).
- Avoid `persistent_term` for this workload because updates can trigger global GC and this command is short-lived.
- ETS is unnecessary in baseline path; consider ETS only if artifact size growth shows map hot spots in profiling.

## 9. Performance and Scalability Plan
### 9.1 Budgets
- Command total runtime: p50 <= 1.0s, p95 <= 3.0s on target corpus.
- JSON parse + normalize: p95 <= 1.2s.
- Semantic compare + severity: p95 <= 600ms.
- Render: p95 <= 200ms.
- Memory ceiling: p95 <= 250MB.

### 9.2 Hotspots & Mitigations
- Large flow lists: use maps/sets, single-pass reduce, avoid nested scans.
- Normalization churn: canonical sort once; reuse normalized structures.
- Mailbox/async overhead: cap any parallel load tasks to two.
- Change fanout: dedupe change keys (`{flow_id, change_type, discriminator}`).

## 10. Failure Modes & Resilience
- Missing base artifact at ref: explicit error with suggested `mix priv_signal.infer --write-lock` + commit.
- Missing candidate workspace artifact: explicit error naming expected path and remediation.
- Unsupported schema version: contract error with supported version list.
- Malformed JSON: parse error with source/path context (base ref object or workspace path).
- Git command failure/timeouts: typed error with command context.
- Optional confidence/scanner section missing:
  - default: warn + continue
  - strict: fail with non-zero exit
- Graceful shutdown: no background workers persist after command exit.

## 11. Observability
### Telemetry Events
- `[:priv_signal, :diff, :run, :start]`
- `[:priv_signal, :diff, :artifact, :load]`
- `[:priv_signal, :diff, :normalize]`
- `[:priv_signal, :diff, :semantic, :compare]`
- `[:priv_signal, :diff, :render]`
- `[:priv_signal, :diff, :run, :stop]`
- `[:priv_signal, :diff, :run, :error]`

### Measurements
- `duration_ms`, `flow_count_base`, `flow_count_candidate`, `change_count`, `high_count`, `medium_count`, `low_count`, `error_count`.

### Metadata (low cardinality)
- `ok`, `format`, `include_confidence`, `schema_version_base`, `schema_version_candidate`, `strict_mode`.
- Do not include raw flow IDs, file paths, or field names as metric tags.

### Logging
- Structured logs with correlation id per run.
- Redact/refuse secret-like payloads from stderr/stdout passthrough.

### Alerts (AppSignal)
- Diff failure rate > 5% over 1 hour.
- Diff runtime p95 > 3.0s for two consecutive 15-minute windows.
- Sudden high-severity count spike > 3x 7-day baseline (advisory alert).

## 12. Security & Privacy
- AuthN/AuthZ: local CLI context only; no remote API surface.
- Tenant isolation: one repo/workspace per run; no shared artifact cache.
- PII handling:
  - compare symbolic identifiers only (field names/categories/sensitivity labels)
  - never emit runtime values.
- Least privilege:
  - read-only git artifact access in diff pipeline.
  - no mutation of working tree or lockfiles.
- Auditability:
  - JSON output includes refs and schema versions for reproducible review.

## 13. Testing Strategy
- Unit tests:
  - normalization invariants
  - semantic category detection
  - severity rule mapping (`rule_id` stability)
  - renderers (human/json)
- Property tests:
  - permutation invariance on input ordering
  - deterministic output hash across repeated runs
- Integration tests:
  - CLI happy paths for human/json outputs
  - missing lockfile / unsupported schema / malformed artifact cases
  - strict vs non-strict optional artifact behavior
- Performance tests:
  - synthetic corpus at 500 flows / 5,000 fields
  - assert runtime and memory budgets in CI benchmark job
- Telemetry tests:
  - verify event emission and metadata shape

## 14. Backwards Compatibility
- Keep infer artifact contract unchanged; diff consumes it read-only.
- Support current schema version and one previous supported version via adapters.
- Preserve existing commands (`infer`, `scan`, `score`, `validate`) without behavior changes.
- Ensure no changes to existing output file defaults unless user opts in.

## 15. Risks & Mitigations
- Risk: flow ID instability causes false add/remove noise.
Mitigation: identity fallback strategy (secondary key from source/entrypoint/sink) behind guarded heuristic.
- Risk: PRD ambiguity on optional scanner/confidence fields.
Mitigation: explicit defaults and strict mode switch in contract.
- Risk: reviewer overload from verbose details.
Mitigation: concise human renderer with severity grouping and capped detail payloads.
- Risk: schema evolution drift between infer and diff.
Mitigation: explicit `PrivSignal.Diff.Contract` and CI compatibility tests with fixtures.

## 16. Open Questions & Follow-ups
- Should artifact path be inferred from config first, then CLI override, or remain CLI/default only?
Recommended default: CLI override > config > default path.
- Should unsupported schema be hard-fail always, or allow best-effort compare?
Recommended default: hard-fail for correctness.
- Do we include confidence diffs by default in CI JSON mode?
Recommended default: no; opt-in to reduce noise.
- Do we need GitHub Check annotations in this phase or defer to next phase?
Recommended default: defer; keep JSON contract stable first.

## 17. References
- Elixir `Task` docs (`async_stream`, concurrency, timeout options) · https://hexdocs.pm/elixir/1.15/Task.html · Accessed 2026-02-08
- Elixir `Task.Supervisor` docs (`async_stream_nolink`) · https://hexdocs.pm/elixir/1.13.4/Task.Supervisor.html · Accessed 2026-02-08
- Telemetry docs (`execute/3`, handler behavior) · https://hexdocs.pm/telemetry/telemetry.html · Accessed 2026-02-08
- Erlang/OTP `persistent_term` docs (read-optimized, global GC update cost) · https://www.erlang.org/doc/apps/erts/persistent_term.html · Accessed 2026-02-08
- Erlang/OTP ETS docs (read/write concurrency trade-offs) · https://www.erlang.org/docs/25/man/ets · Accessed 2026-02-08
- Erlang OTP Design Principles Overview (supervision/worker model) · https://www.erlang.org/docs/20/design_principles/des_princ.html · Accessed 2026-02-08
- Erlang `gen_server` docs (behavior and supervision alignment) · https://www.erlang.org/docs/23/man/gen_server · Accessed 2026-02-08
