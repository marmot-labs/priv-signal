# Enhanced PII Node Inventory — FDD

## 1. Executive Summary
This design upgrades PrivSignal scanner output from finding-centric records to a deterministic node inventory that is ready for future Proto Flow inference. It affects developers, privacy reviewers, and CI maintainers by producing a stable JSON artifact that can be diffed and versioned across runs. The implementation reuses the existing scanner pipeline (`PrivSignal.Scan.Runner`, `PrivSignal.Scan.Logger`, `PrivSignal.Scan.Inventory`) and introduces a normalization layer that emits node contracts independent of any single scanner rule. The first productionized node source remains logging sinks, while entrypoint classification is added as scaffolding metadata and optional node generation. The architecture keeps flow inference out of scope and enforces a strict boundary: scanners discover local evidence; the node layer canonicalizes identity; output writers serialize. OTP alignment remains lightweight and robust: bounded `Task.Supervisor.async_stream_nolink/6`, per-file failure isolation, deterministic reduction, and no long-lived global bottleneck process. Performance posture is CI-safe by design with bounded concurrency, immutable shared inventory, and deterministic sort/fingerprint finalization. Privacy posture is improved because artifacts contain symbol-level code evidence only, never runtime values, and telemetry/log metadata remains cardinality-safe. The highest risks are identity instability and schema drift; both are mitigated with canonical identity rules, schema versioning, and property tests. This design also addresses command-surface drift by introducing `mix priv_signal.scan` as the canonical entrypoint while preserving compatibility with `mix priv_signal.scan`.

## 2. Requirements & Assumptions
### Functional Requirements
- FR-001: logging scanner emits normalized `sink` nodes instead of ad-hoc findings.
- FR-002: canonical node schema is enforced (`id`, `node_type`, `pii`, `code_context`, `role`, `evidence`, `confidence`).
- FR-003: node IDs are deterministic and derived from semantic identity only.
- FR-004: file paths are normalized to repo-relative POSIX style.
- FR-005: module and function identity is canonicalized (`Module.Name`, `function/arity`).
- FR-006: nodes are consistently sorted before serialization.
- FR-007: PII metadata captured per node (`reference`, `category`, `sensitivity`).
- FR-008: role metadata captured with `sink.kind=logger` in this phase.
- FR-009: entrypoint classification scaffolding includes confidence and evidence signals.
- FR-010: AST-backed evidence list is emitted per node.
- FR-011: inventory generation is integrated in infer command artifacts.
- FR-012: output is generated-only and developer-reviewable.
- FR-013: schema version exists for forward compatibility.
- FR-014: no inferred edges in this phase.

### Non-Functional Requirements
- Determinism: byte-stable node list for identical repo+config inputs.
- Performance: inventory phase p50 <= 5s and p95 <= 20s at ~5,000 Elixir files.
- Throughput: target >= 250 files/s p50 for parseable files.
- Memory: <= 700MB RSS p95 in CI.
- Reliability: partial file failures recorded without dropping successful node generation.
- Observability: scan lifecycle telemetry and rollout health metrics emitted for AppSignal.
- Security: no runtime PII values in logs/artifacts/telemetry.

### Explicit Assumptions
- A1: Existing `PrivSignal.Scan.Logger` and `PrivSignal.Scan.Runner` remain the execution backbone.
Impact: delivery is incremental and low-risk but constrained by current AST extraction strategy.
- A2: The repo currently exposes `mix priv_signal.scan`; `mix priv_signal.scan` will be introduced as alias/new task.
Impact: rollout includes command compatibility and docs migration.
- A3: Artifact storage remains file-based and no database persistence is introduced.
Impact: no Ecto migration needed in this phase.
- A4: Module classification is heuristic and non-blocking.
Impact: classification errors cannot fail the run; confidence/evidence must be included.
- A5: Single-node CLI/CI runtime remains the default topology.
Impact: multi-node cache coherence is documented but not required at runtime.

## 3. Torus Context Summary
### What I Know
- Scanner execution today is task-parallel and bounded in `PrivSignal.Scan.Runner` using `Task.Supervisor.async_stream_nolink/6` with timeout and `on_timeout: :kill_task`.
- Scanner currently produces `PrivSignal.Scan.Finding` records with IDs including line numbers and evidence types.
- Source enumeration is deterministic (`PrivSignal.Scan.Source.files/1` sorts file list).
- PII inventory source of truth is already `config.pii` (`PrivSignal.Config`, `PrivSignal.Config.Schema`, `PrivSignal.Config.PII`).
- Telemetry wrapper exists (`PrivSignal.Telemetry.emit/3`) and scan events are already emitted (`inventory build`, `run`, `output write`).
- Runtime startup is CLI-local via `PrivSignal.Runtime.ensure_started/0`; there is no long-lived app supervision tree for scan work.
- Mix task surface currently includes `priv_signal.scan`, `score`, `validate`, `init`; no `priv_signal.infer` task exists yet.

### What I Don’t Know Yet
- Whether `mix priv_signal.scan` should fully replace `scan` now or coexist long-term.
- Final default path/name for the node inventory artifact in CI.
- Final taxonomy governance for `pii.category` and sensitivity extensions.
- Exact rollout gate policy for enabling enhanced inventory by default in all repos.

### Domain/Boundary Summary
- Config domain: `PrivSignal.Config.*` owns parsing and schema validation.
- Scanner domain: `PrivSignal.Scan.*` owns source enumeration, AST matching, classification, and output.
- Validation/scoring domain: `PrivSignal.Validate.*` and `PrivSignal.Risk.*` remain separate and unaffected by node inference scope.
- Deployment: CLI command in developer shells and CI jobs, single-repo boundary per run.
- Tenancy: repository is isolation boundary; no runtime tenant multiplexing.

## 4. Proposed Design
### 4.1 Component Roles & Interactions
- `PrivSignal.Infer.Runner` (new): orchestration entrypoint for node inventory generation; wraps/extends scan runner behavior.
- `PrivSignal.Infer.ScannerAdapter` (new): converts scanner-specific candidate outputs into a unified candidate touchpoint shape.
- `PrivSignal.Infer.Node` (new struct): canonical node model used across all scanner types.
- `PrivSignal.Infer.NodeIdentity` (new): deterministic identity derivation from canonical semantic inputs.
- `PrivSignal.Infer.NodeNormalizer` (new): applies path/module/function canonicalization, confidence defaults, role normalization.
- `PrivSignal.Infer.ModuleClassifier` (new): heuristically tags module role (`controller`, `liveview`, `job`, `worker`) with confidence signals.
- `PrivSignal.Infer.InventoryWriter` (new): writes schema-versioned JSON artifact with sorted nodes.
- `PrivSignal.Scan.Logger` (existing, updated): continues to detect logging evidence and now emits adapter-compatible candidates.
- `Mix.Tasks.PrivSignal.Scan` (new): primary CLI command for node inventory.
- `Mix.Tasks.PrivSignal.Scan` (existing, compatibility mode): retained temporarily; can delegate to infer with legacy output format option.

Interaction flow:
1. Load validated config.
2. Build normalized PII inventory.
3. Enumerate source files deterministically.
4. Run scanner workers in bounded parallelism.
5. Transform candidates to canonical nodes.
6. Generate deterministic IDs.
7. Sort nodes.
8. Serialize versioned artifact and emit telemetry.

### 4.2 State & Message Flow
- State ownership:
- Immutable shared state: normalized PII inventory and infer options.
- Per-worker state: AST, module/function context, transient candidate list.
- Reducer state: accumulated candidates/errors and final node list.

Message flow:
1. Runner emits `run_started` telemetry with static metadata.
2. Workers return `{:ok, file, candidates}` or `{:error, file, reason}`.
3. Reducer merges results incrementally to avoid unbounded mailbox pressure.
4. Normalizer/classifier converts candidates to nodes.
5. Node identity module computes deterministic ID.
6. Writer emits artifact and completion telemetry.

Backpressure points:
- `max_concurrency` capped (existing cap 8 remains default, configurable).
- Worker timeout enforced.
- Ordered stream remains `ordered: false` to reduce buffering; determinism restored by final stable sort.

### 4.3 Supervision & Lifecycle
- Infer run starts a temporary `Task.Supervisor` owned by caller process.
- Child restart mode remains temporary; crashed/timeout tasks are isolated and recorded as operational errors.
- No persistent process introduced for node storage.
- Lifecycle is command-scoped: startup, scan, reduce, write, exit.
- Failure isolation:
- Fatal preconditions (invalid config, output write failure) return non-zero.
- File-level parse failures are non-fatal unless strict mode.

### 4.4 Alternatives Considered
- Alternative A: Replace scanner core with single long-lived GenServer pipeline.
Why rejected: introduces bottleneck state owner and unnecessary runtime lifecycle for CLI workload.
- Alternative B: Emit nodes directly from `Scan.Logger` only.
Why rejected: couples node schema to one scanner and blocks future HTTP/DB/telemetry scanners.
- Alternative C: Persist nodes in Postgres for diffing.
Why rejected: out of scope, adds migrations/ops burden, and violates current artifact-based workflow.
- Recommended approach: keep scanner adapters lightweight, centralize canonicalization and identity in infer layer, retain bounded task parallelism.

## 5. Interfaces
### 5.1 HTTP/JSON APIs
- No network API changes.
- JSON artifact contract (new infer output):
- top-level: `schema_version`, `tool`, `git`, `summary`, `nodes`, `errors`.
- node-level: `id`, `node_type`, `pii`, `code_context`, `role`, `confidence`, `evidence`.
- Rate limits: not applicable.

### 5.2 LiveView
- Not applicable in current CLI architecture.
- If future UI consumers are added, they must consume versioned artifact contracts only.

### 5.3 Processes
- Runner uses `Task.Supervisor.async_stream_nolink/6`.
- No Registry required in phase scope.
- No GenStage/Broadway required; task-stream model is sufficient and simpler.
- Optional future extension: partitioned supervisors for very large repos if startup supervisor becomes a bottleneck.

## 6. Data Model & Storage
### 6.1 Ecto Schemas
- No Ecto schema changes in this phase.
- New in-memory structs:
- `PrivSignal.Infer.Node`
- `PrivSignal.Infer.EvidenceSignal`
- `PrivSignal.Infer.ModuleClassification`

Proposed `PrivSignal.Infer.Node` fields:
- `id :: String.t()`
- `node_type :: :entrypoint | :source | :sink | :transform`
- `pii :: [%{reference: String.t(), category: String.t(), sensitivity: String.t()}]`
- `code_context :: %{module: String.t() | nil, function: String.t() | nil, file_path: String.t(), lines: [non_neg_integer()]}`
- `role :: map()`
- `confidence :: float()`
- `evidence :: [%{rule: String.t(), signal: String.t(), line: integer() | nil, ast_kind: String.t()}]`

Migration/index plan:
- No DB migration.
- Artifact schema migration via `schema_version`.

### 6.2 Query Performance
- No SQL path.
- File scan path:
- O(total_ast_nodes) traversal across files.
- O(n log n) deterministic sort for `n` nodes.
- Expected plan for large repositories:
- CPU-bound parse/traversal.
- IO-bound file reading during source expansion.
- Mitigation: bounded concurrency and no full-project AST retention.

## 7. Consistency & Transactions
- Consistency model: deterministic eventual completion for one run.
- Transaction boundaries:
- Config validation must succeed before scanning.
- File scans are independent units.
- Node normalization and ID derivation happen after candidate accumulation.
- Idempotency:
- Same config + same file contents => identical `id` and sorted node list.
- Retries:
- per-file read retry at most 2 attempts for transient read errors.
- Compensation:
- non-fatal file parse errors included in `errors` with file path and reason.

Identity consistency rule:
- `id` uses canonical semantic tuple only:
- `{node_type, canonical_module, canonical_function_arity, normalized_file_path, pii_reference_set, role_kind}`
- Excludes line numbers, evidence ordering, timestamps, and run environment.

## 8. Caching Strategy
- Layer 1: In-run immutable PII inventory map from config (existing).
- Layer 2: Optional ETS cache for module classification results per file/module:
- table type `:set`
- options `read_concurrency: true`, `write_concurrency: true`
- owner is infer runner process
- destroyed at run end
- Layer 3: no persistent cross-run cache in phase 1.

Invalidation:
- In-run only, no explicit TTL required.
- If cross-run cache is introduced later, key must include file content hash + scanner version + schema version.

Multi-node coherence:
- N/A for current CLI topology.

Rationale:
- Avoid `persistent_term` because updates trigger global GC and it is intended for infrequently updated data.

## 9. Performance and Scalability Plan
### 9.1 Budgets
- Inventory generation: p50 <= 5s, p95 <= 20s, p99 <= 30s at 5k files.
- File throughput: >= 250 files/s p50.
- Memory budget: <= 700MB RSS p95.
- Mailbox guardrail: runner mailbox length should remain bounded by stream consumption; alert if > 10,000 messages in perf stress tests.
- Task concurrency default: `min(System.schedulers_online(), 8)` with upper hard cap 16 for future tuning.

### 9.2 Hotspots & Mitigations
- Hotspot: AST parse CPU spikes on large files.
Mitigation: concurrency cap + timeout + best-effort error capture.
- Hotspot: node cardinality growth from broad heuristics.
Mitigation: explicit rule scopes and evidence caps per node.
- Hotspot: determinism drift from map/object ordering.
Mitigation: sort node list explicitly and derive IDs from canonical tuple serialization.
- Hotspot: large evidence payloads inflate artifact size.
Mitigation: cap evidence entries per node and include only structured fields.

## 10. Failure Modes & Resilience
- Invalid config/schema: fail fast, no output artifact.
- Unreadable or unparsable file: add parse error record and continue unless strict mode.
- Worker timeout: kill task, increment timeout counter, continue.
- Output write failure: return non-zero, keep in-memory summary for CLI diagnostics.
- Telemetry handler failure: do not crash scan pipeline; rely on `:telemetry` handler-failure isolation semantics.
- Graceful shutdown: task supervisor termination closes outstanding tasks; no persistent state to recover.

Retry/backoff policies:
- File read transient failures: retry up to 2 with jittered backoff (25ms, 75ms).
- No retries for parse errors (deterministic input-level failures).

## 11. Observability
Proposed telemetry events:
- `[:priv_signal, :infer, :run, :start]`
- `[:priv_signal, :infer, :inventory, :build]`
- `[:priv_signal, :infer, :scan, :file]`
- `[:priv_signal, :infer, :run, :stop]`
- `[:priv_signal, :infer, :output, :write]`

Measurements:
- `duration_ms`, `file_count`, `node_count`, `error_count`, `parse_error_count`, `timeout_count`.

Metadata:
- `schema_version`, `scanner_version`, `strict_mode`, `ok`, `node_types_present`.

Cardinality guardrails:
- No file paths, PII field names, or raw expressions in telemetry metadata.
- Structured logs can include file paths in debug mode only; never include runtime values.

AppSignal dashboards/alerts:
- Duration p95 > 20s for 30 minutes.
- Fatal run failure > 2% over 1h.
- Determinism mismatch counter > 0 in canary cohort.

## 12. Security & Privacy
- AuthN/AuthZ: CLI only; execution rights follow repo/CI permissions.
- Tenant isolation: repository boundary only; no cross-repo reads.
- PII policy:
- Never include runtime values in node evidence.
- Include only static references (`User.email`) and AST signal descriptors.
- Artifact hygiene:
- include scanner version and commit SHA for auditability.
- redact any accidental literal capture from evidence rendering logic.
- Least privilege:
- infer flow requires no external network calls.

## 13. Testing Strategy
Unit tests:
- Canonical path normalization and module/function canonicalization.
- Identity generation excludes line numbers and timestamps.
- Module classifier evidence/confidence behavior.

Property tests:
- Deterministic node IDs across randomized file order.
- Deterministic sorted output across repeated runs.
- Equivalence under line-shift-only edits (same identity, changed evidence line).

Integration tests:
- `mix priv_signal.scan` writes schema-versioned node artifact.
- `mix priv_signal.scan` compatibility path still works during migration window.
- strict vs best-effort behavior.

Resilience tests:
- parse failures, worker timeouts, output write errors.
- telemetry emission under partial failures.

Security tests:
- artifact/log/telemetry do not contain runtime values or secrets.

## 14. Rollout & Migration Plan
- Feature flag: `enhanced_pii_inventory`.
- Default rollout:
- dev/stage enabled.
- prod CI canary enabled for selected repos.
- global enable after KPI stability.

Migration steps:
1. Add `Mix.Tasks.PrivSignal.Scan` as the primary command.
2. Emit both legacy findings and new nodes behind flag for one release.
3. Validate node determinism hash and coverage parity vs logging findings.
4. Switch default artifact to node inventory.
5. Deprecate legacy finding format in subsequent minor release.

Rollback:
- toggle feature flag off.
- revert to existing finding-only scan output path.
- retain compatibility task and parser for one minor release.

## 15. Risks & Mitigations
- Risk: identity collisions for semantically different nodes.
Mitigation: include role kind and normalized PII reference set in canonical tuple; add collision tests.
- Risk: identity churn during refactors (module rename/path move).
Mitigation: accept churn as semantic change; provide migration note and diff tooling guidance.
- Risk: command confusion between `scan` and `infer`.
Mitigation: explicit CLI messaging, alias period, docs update, deprecation warnings.
- Risk: entrypoint classifier false positives.
Mitigation: keep non-blocking classification with confidence and evidence signals.
- Risk: telemetry cardinality explosion.
Mitigation: enforce metadata whitelist and test assertions.

## 16. Open Questions & Follow-ups
- Should `mix priv_signal.scan` become the only command immediately, or remain parallel with `scan` for one release?
Suggested default: parallel for one minor release.
- Should artifact include `generated_at` if lockfile diffs are expected to be clean?
Suggested default: omit from lockfile payload, include in sidecar metadata only.
- Should entrypoint nodes be emitted independently in this phase or only as context on sink nodes?
Suggested default: emit context now; standalone entrypoint nodes behind secondary flag.
- Should future HTTP/DB/telemetry scanners share one adapter contract now?
Suggested default: yes, define adapter interface now to avoid schema drift later.

## 17. References
- Elixir `Task.Supervisor` docs · https://hexdocs.pm/elixir/Task.Supervisor.html · Accessed February 8, 2026
- Elixir `Task` docs · https://hexdocs.pm/elixir/Task.html · Accessed February 8, 2026
- Elixir `Supervisor` docs · https://hexdocs.pm/elixir/Supervisor.html · Accessed February 8, 2026
- Telemetry docs (`execute/3`, handler semantics) · https://hexdocs.pm/telemetry/telemetry.html · Accessed February 8, 2026
- Erlang/OTP ETS docs · https://www.erlang.org/doc/apps/stdlib/ets.html · Accessed February 8, 2026
- Erlang/OTP `persistent_term` docs · https://www.erlang.org/doc/apps/erts/persistent_term.html · Accessed February 8, 2026
- Elixir `Path` docs (`relative_to/2`, `relative_to_cwd/1`, `safe_relative_to/2`) · https://hexdocs.pm/elixir/Path.html · Accessed February 8, 2026
- AppSignal Elixir instrumentation guide · https://docs.appsignal.com/elixir/instrumentation/integrating-appsignal.html · Accessed February 8, 2026
- AppSignal Elixir integrations overview · https://docs.appsignal.com/elixir/integrations.html · Accessed February 8, 2026
- RFC 8259 (JSON objects unordered; arrays ordered) · https://www.rfc-editor.org/rfc/rfc8259 · Accessed February 8, 2026
