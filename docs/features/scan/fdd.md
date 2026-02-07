# FDD: PII Inventory and Logging Scanner

## 1. Executive Summary
This feature adds a deterministic scanner that builds a project-specific PII inventory from `priv-signal.yml` and finds logging statements that may expose declared PII. The immediate audience is developers, reviewers, and privacy engineers who need actionable evidence before or during PR review. The design keeps scanner logic fully local and AST-based, with no LLM dependency, so repeated runs on the same input produce the same output. The scanner is introduced as an additive capability through a dedicated `mix priv_signal.scan` task, while preserving current `mix priv_signal.score` and `mix priv_signal.validate` behavior by default. The configuration model is cut over so `pii` is the only supported source of PII declarations, and `validate`/`score` consume the same normalized PII inventory used by the scanner. The pipeline is file-parallel and bounded with `Task.Supervisor.async_stream_nolink`, preventing a single failing parse from crashing the whole run. Findings are classified as `confirmed_pii` or `possible_pii`, include module/function/file/line evidence, and never include runtime PII values. The performance posture targets CI-scale repositories with bounded concurrency, deterministic sorting, and no long-lived per-node cache requirement. Key risks are false positives from bulk logging heuristics and alias/wrapper resolution gaps; both are contained by confidence labeling and explicit v1 scope boundaries.

## 2. Requirements and Assumptions
### Functional Requirements
- `SCN-FR-01` PII declarations: support `pii` entries with `module` and field metadata (`name`, `category`, `sensitivity`) as authoritative scanner input.
- `SCN-FR-02` Inventory build: create deterministic in-memory inventory of PII modules, fields, and normalized key variants used for AST matching.
- `SCN-FR-03` Logging sink scan: detect `Logger.<level>`, `Logger.log/2`, and `:logger.*` sink calls in parsed AST.
- `SCN-FR-04` Evidence extraction: produce location and context (`module`, `function`, `arity`, `file`, `line`, sink signature, matched fields).
- `SCN-FR-05` Classification: label findings `confirmed_pii` for direct evidence and `possible_pii` for indirect/suspicious evidence.
- `SCN-FR-06` Output: generate Markdown and JSON reports containing only PII-relevant findings.
- `SCN-FR-07` Cutover: `pii` is the only supported PII config source for scan, validate, and score.
- `SCN-FR-08` Existing workflows: `mix priv_signal.validate` and `mix priv_signal.score` continue to work after cutover by reading normalized `pii` inventory.
- `SCN-FR-09` Error separation: distinguish configuration/parsing/indexing failures from scan findings.

### Non-Functional Requirements
- Determinism: identical config + source tree yields byte-stable sorted findings.
- Performance: P95 scanner runtime <= 12s on a typical CI worker for ~2,000 Elixir files.
- Resource bounds: peak memory <= 350 MB for scanner run; bounded task concurrency.
- Explainability: each finding must carry machine-readable evidence tokens and human-readable summary.
- Extensibility: sink analyzers are pluggable by sink type to support future non-logging sinks.

### Explicit Assumptions
- `SCN-A-01` v1 analyzes Elixir source files (`*.ex`, `*.exs`) only.
  Impact: generated code or runtime-only modules are out of scope.
- `SCN-A-02` alias/wrapper logger indirection is limited in v1 (direct `Logger` and `:logger` calls prioritized).
  Impact: some true positives become `possible_pii` or are missed.
- `SCN-A-03` no DB persistence is required; scanner artifacts are per-run files.
  Impact: no migration/backfill burden in v1.
- `SCN-A-04` scanner remains advisory; findings do not fail builds by default.
  Impact: teams that want gating need explicit CI policy wrapping.

## 3. Context Summary
### Current architecture and boundaries
- CLI entrypoints are Mix tasks (`lib/mix/tasks/priv_signal.*.ex`), not a long-running OTP app.
- Runtime bootstrap (`lib/priv_signal/runtime.ex`) ensures `:telemetry`, `:finch`, and `:req` are started and creates `Req.Finch`.
- Config is loaded/validated via `PrivSignal.Config.Loader` + `PrivSignal.Config.Schema`; current code centers on `pii_modules` and `flows`, which this design cuts over to `pii` + `flows`.
- Deterministic AST indexing already exists in `PrivSignal.Validate.AST` and `PrivSignal.Validate.Index`.
- Telemetry is emitted through a thin wrapper (`PrivSignal.Telemetry.emit/3`) and currently covers config, validation, git diff, LLM request, risk assess, and output write.
- Output rendering uses dedicated modules for Markdown/JSON and a shared writer.

### Runtime topology, deployment, and tenancy
- Single-node execution model in developer shell or CI job.
- No tenant multiplexing in runtime; one repository root and one `priv-signal.yml` per run.
- Failure domain is the invoking Mix task process plus spawned task workers.

### What I know
- Deterministic AST parsing and symbol indexing patterns already exist and are test-covered.
- Existing validation flow already runs before score; this can remain unchanged.
- Current telemetry conventions use low-overhead measurement maps and simple metadata.

### What I do not know yet
- Preferred default CLI semantics for `mix priv_signal.scan` vs optional score integration.
- Desired strictness for parse errors in heterogeneous monorepos (best-effort vs fail-fast).
- Whether logger wrapper resolution is required in v1 or deferred to v1.1.

## 4. Proposed Design
### 4.1 Component Roles and Interactions
- `PrivSignal.Config` (update):
  - Replace `pii_modules` with canonical `pii` declarations.
  - New structs:
    - `PrivSignal.Config.PIIEntry` (`module`, `fields`)
    - `PrivSignal.Config.PIIField` (`name`, `category`, `sensitivity`)
- `PrivSignal.Config.Schema` (update):
  - Require and validate `pii` section.
  - Reject configs that still declare `pii_modules` with a clear migration error.
  - Build a normalized PII inventory consumed by scan, validate, and score.
- `PrivSignal.Scan.Inventory`:
  - Build normalized lookup maps:
    - by module
    - by field name
    - by derived key token (`"email"`, `:email`, `"email_address"` if explicitly declared)
- `PrivSignal.Scan.Source`:
  - Resolve source files deterministically (sorted) using project root + Mix `elixirc_paths`.
- `PrivSignal.Scan.Runner`:
  - Orchestrate scan lifecycle.
  - Spawn bounded file analysis workers via `Task.Supervisor.async_stream_nolink`.
  - Aggregate/dedupe/sort findings.
- `PrivSignal.Scan.Logger`:
  - Traverse AST with context stack (`module`, `function`, `arity`, lexical bindings).
  - Identify logging sinks and extract candidate evidence nodes.
- `PrivSignal.Scan.Classifier`:
  - Emit `confirmed_pii` / `possible_pii`.
  - Compute sensitivity summary based on highest matched field sensitivity.
- `PrivSignal.Scan.Output.JSON` and `PrivSignal.Scan.Output.Markdown`:
  - Render scanner-specific outputs (separate from risk scoring output module).
- `Mix.Tasks.PrivSignal.Scan`:
  - New entrypoint for scanner-only workflow.

### 4.2 State and Message Flow
- State ownership:
  - Inventory state is immutable and shared by value to workers.
  - Per-file traversal state is owned by each worker task.
  - Aggregated findings are owned by the runner process.
- Message flow:
  1. Runner loads config and builds inventory.
  2. Runner enumerates source files.
  3. Runner dispatches file work items to supervised tasks.
  4. Each task returns `{:ok, findings}` or `{:error, parse_error}`.
  5. Runner folds responses into accumulator, classifies, dedupes, sorts, emits outputs.
- Backpressure points:
  - `max_concurrency` bound set from schedulers (`min(System.schedulers_online(), 8)` default).
  - `Task.Supervisor.async_stream_nolink` with `timeout` and `on_timeout: :kill_task`.
  - Stream consumption is incremental; no full raw AST retention.

### 4.3 Supervision and Lifecycle
- Scanner task lifecycle is short-lived and scoped to Mix command execution.
- `Task.Supervisor` is started for scan execution (`restart: :temporary`) and terminated when command exits.
- Failure isolation:
  - Worker crashes do not crash caller (`async_stream_nolink`); runner records scan errors.
  - Configuration errors fail fast before spawning workers.
- Tree placement:
  - No global supervision tree change required for v1.
  - Optional future enhancement: start named task supervisor in `PrivSignal.Runtime`.

### 4.4 Alternatives Considered
- Alternative A: regex/text scanning only.
  - Rejected: too noisy, poor explainability for module/function context.
- Alternative B: BEAM debug_info reflection after compile.
  - Rejected: requires compile assumptions and loses direct source-line fidelity in modified files.
- Alternative C: GenServer central analyzer.
  - Rejected: creates a bottleneck process without runtime-state need; pure functional + task stream is simpler and safer.
- Chosen approach: deterministic AST traversal with bounded file-parallel workers.

### 4.5 Config Cutover and Existing Workflow Alignment
- Cutover objective:
  - Make `pii` the single source of truth across all features.
- Implementation steps:
  1. Update `PrivSignal.Config` struct to remove `pii_modules` and add canonical `pii` entries.
  2. Update `PrivSignal.Config.Schema` to require `pii` and return actionable errors when `pii_modules` appears.
  3. Add `PrivSignal.Config.PII` normalization helpers that expose:
     - declared PII modules
     - declared fields
     - key tokens used by scanner matching
  4. Update `PrivSignal.Validate.run/2` to read module validation inputs from normalized `pii` declarations.
  5. Update `PrivSignal.Config.Summary.build/1` and `PrivSignal.LLM.Prompt` input summary so score uses normalized `pii` declarations (and derived module list where needed by current risk logic).
  6. Update `mix priv_signal.init` sample config and README docs to emit only `pii`.
  7. Add regression tests proving `validate` and `score` behavior remains operational under the new schema.
- Rollout mode:
  - Single-release cutover with explicit config error for legacy key, plus migration example in error text.

## 5. Interfaces
### 5.1 HTTP/JSON APIs
- No network-facing API introduced in v1.
- JSON file artifact schema:
  - `scanner_version`
  - `summary` (`confirmed_count`, `possible_count`, `high_sensitivity_count`, `files_scanned`, `errors`)
  - `inventory` (`modules`, `field_count`)
  - `findings[]` with location, sink, evidence, confidence, sensitivity

### 5.2 LiveView
- Not applicable: PrivSignal is currently a CLI tool, no Phoenix/LiveView surface.

### 5.3 Processes
- Runner process invokes:
  - `Task.Supervisor.start_link/1`
  - `Task.Supervisor.async_stream_nolink/4`
- No long-lived Registry keys required in v1.
- No GenStage/Broadway pipeline needed; workload is bounded and synchronous to command execution.

## 6. Data Model and Storage
### 6.1 Ecto Schemas
- No Ecto schema or DB migration is required in v1.
- In-memory structs added:
  - `PrivSignal.Config.PIIEntry`
  - `PrivSignal.Config.PIIField`
  - `PrivSignal.Scan.Finding`
  - `PrivSignal.Scan.Evidence`
- `priv-signal.yml` cutover plan:
  1. Require `pii` immediately for all commands.
  2. Return schema error when `pii_modules` is present.
  3. Provide migration guidance in `mix priv_signal.validate`/`score` failure output.
  4. Keep one canonical normalization path for scan, validate, and score.
- Constraints:
  - `module`: non-empty string.
  - `fields`: non-empty list.
  - `field.name`: non-empty string.
  - `sensitivity`: enum (`low|medium|high`) with default `medium`.
  - `category`: non-empty string (informational, not policy-enforced in v1).

### 6.2 Query Performance
- No SQL query path in v1.
- Representative in-memory operations:
  - Field match lookup: O(1) map/set membership.
  - Per-file AST traversal: O(nodes_in_file).
  - Global scan complexity: O(total_ast_nodes + findings log findings) due to final sort.
- Expected plan:
  - CPU bound in AST traversal; memory bound by concurrent AST worker count.

## 7. Consistency and Transactions
- Consistency model: strong deterministic consistency for a single scan run.
- Transaction boundaries:
  - Config load/validate: atomic precondition.
  - File analysis: independently retriable units.
  - Aggregation: pure reduction after worker results.
- Idempotency:
  - Same commit + same config => identical sorted output.
  - Finding IDs derived from deterministic fingerprint (`file:line:sink:fields` hash) rather than random integers.
- Compensation:
  - If one file fails parse, report file-scoped error and continue (default best-effort mode).
  - Optional strict mode can treat any parse error as command failure.

## 8. Caching Strategy
- v1 default: no persistent cross-run cache.
- In-run cache:
  - Optional ETS table for inventory-derived tokens (`:set`, protected, `read_concurrency: true`, `write_concurrency: false`).
  - Table owner is runner process; auto-destroy on process exit.
- Invalidation:
  - Not needed across runs because cache lifetime == command lifetime.
- Multi-node coherence:
  - Not applicable in current single-node CLI execution.
- `persistent_term` is not recommended for v1 scanner metadata due update cost and global GC effects.

## 9. Performance and Scalability Plan
### 9.1 Budgets
- Target scan runtime:
  - P50 <= 4s
  - P95 <= 12s
  - P99 <= 20s
- Max allocations/op:
  - <= 5 MB per analyzed file task (soft target, measured in profiling runs).
- Repo pool sizing:
  - Not applicable (no DB Repo usage).
- ETS memory ceiling:
  - <= 32 MB when optional in-run ETS cache is enabled.

### 9.2 Hotspots and Mitigations
- Hotspot: AST parse CPU spikes on large files.
  - Mitigation: bounded concurrency + per-task timeout.
- Hotspot: finding explosion from noisy heuristics.
  - Mitigation: v1 heuristics constrained to declared PII keys/modules; confidence labeling.
- Hotspot: nondeterministic output ordering under concurrency.
  - Mitigation: deterministic final sort + stable fingerprint dedupe.
- Hotspot: mailbox growth on runner under fast producer.
  - Mitigation: streaming fold, bounded `max_concurrency`, no unbounded buffering.

## 10. Failure Modes and Resilience
- Config malformed (`pii` invalid):
  - Fail fast with explicit schema errors.
- File unreadable or unparsable:
  - Record scan error with file path, continue in best-effort mode.
- Worker timeout:
  - Kill task, emit timeout error entry, continue run.
- Scanner output write failure:
  - Print findings to stdout; return non-zero with file write reason.
- Graceful shutdown:
  - Task supervisor uses temporary children; unfinished tasks terminated on command shutdown.
- Retry policy:
  - No automatic retries in v1 to preserve deterministic and predictable latency.

## 11. Observability
- Telemetry events (proposed):
  - `[:priv_signal, :scan, :inventory, :build]`
  - `[:priv_signal, :scan, :run]`
  - `[:priv_signal, :scan, :output, :write]`
- Measurements:
  - `duration_ms`, `file_count`, `finding_count`, `confirmed_count`, `possible_count`, `error_count`
- Metadata:
  - `ok`, `strict_mode`, `format`, `scanner_version`
- Cardinality guardrails:
  - Do not include raw file paths or field names in telemetry metadata (keep them in report artifacts only).
- Logs:
  - Structured CLI lines for summary and top errors.
  - Never log PII values; only symbols and static references.
- SLO alert suggestions:
  - P95 duration > 12s (warning)
  - parse error rate > 2% files (warning)
  - output write failure > 0 (critical)
- OpenTelemetry/AppSignal bridge:
  - Keep using `:telemetry`; downstream teams can attach `opentelemetry_telemetry`/AppSignal handlers externally.

## 12. Security and Privacy
- AuthN/AuthZ:
  - Not applicable in-process CLI context.
- Tenant isolation:
  - Repository-level boundary; scanner reads only local workspace files.
- PII handling:
  - Scanner never evaluates runtime values; evidence is symbol-level only.
  - Report redaction policy: no inspected runtime terms, only AST-derived references.
- Auditability:
  - JSON report includes deterministic finding IDs and scanner version for traceability.
- Least privilege:
  - No network calls required for scanner path.

## 13. Testing Strategy
- Unit tests:
  - config schema validation for required `pii` section and rejection of `pii_modules`.
  - inventory normalization and key-derivation logic.
  - classifier rules (`confirmed_pii` vs `possible_pii`).
- Integration tests:
  - `mix priv_signal.scan` end-to-end fixture repo with deterministic expected JSON and Markdown snapshots.
  - ensure `mix priv_signal.score` behavior is unchanged unless scan explicitly enabled.
- Concurrency/race tests:
  - task timeout and worker crash handling.
  - deterministic output ordering under varied scheduler counts.
- Failure injection:
  - malformed file AST, unreadable file, output write errors.
- Given/When/Then acceptance checks:
  - Given valid `pii` declarations and logging code with `user.email`, when running scanner, then one `confirmed_pii` finding is reported with file/function/line.
  - Given logging of `inspect(params)` and `params` key overlap with declared PII fields, when running scanner, then one `possible_pii` finding is reported.
  - Given malformed `pii` config, when running scanner, then command exits non-zero with schema errors and no false finding payload.
  - Given a config using deprecated `pii_modules`, when running scan/validate/score, then command exits non-zero with explicit migration instructions.

## 15. Risks and Mitigations
- Risk: false positives from broad key matching.
  - Mitigation: keep heuristic set narrow, classify as `possible_pii`, and expose evidence type.
- Risk: false negatives for wrapper logging functions.
  - Mitigation: document v1 limitation; add alias/wrapper resolution in v1.1 backlog.
- Risk: performance regression on large monorepos.
  - Mitigation: concurrency cap, timeout, and benchmark gate in CI.
- Risk: config cutover friction from `pii_modules` to `pii`.
  - Mitigation: explicit schema error text with rewrite example + updated `mix priv_signal.init` template + README migration note.
- Risk: report schema drift over time.
  - Mitigation: versioned scanner artifact (`scanner_version`) and golden-file tests.

## 16. Open Questions and Follow-ups
- Should `mix priv_signal.score` gain `--scan` support in v1, or keep scanner strictly separate first?
  - Suggested default: separate command in v1, optional integration in next increment.
- Should parse errors default to best-effort or strict failure?
  - Suggested default: best-effort + `--strict` opt-in for CI hard gating.
- Should `category`/`sensitivity` map into current risk categories immediately?
  - Suggested default: keep scanner report independent in v1; integrate with risk policy later.
- Should logger wrapper resolution be required for launch?
  - Suggested default: defer to v1.1 unless blocker repositories rely heavily on wrappers.

## 17. References
- [R1] Elixir `Task` docs · https://hexdocs.pm/elixir/Task.html · Accessed February 7, 2026
- [R2] Elixir `Task.Supervisor` docs · https://hexdocs.pm/elixir/Task.Supervisor.html · Accessed February 7, 2026
- [R3] Elixir `Supervisor` docs · https://hexdocs.pm/elixir/Supervisor.html · Accessed February 7, 2026
- [R4] Elixir `GenServer` docs · https://hexdocs.pm/elixir/GenServer.html · Accessed February 7, 2026
- [R5] Elixir `Code.string_to_quoted/2` docs · https://hexdocs.pm/elixir/Code.html#string_to_quoted/2 · Accessed February 7, 2026
- [R6] `telemetry` README (HexDocs) · https://hexdocs.pm/telemetry/readme.html · Accessed February 7, 2026
- [R7] Elixir `Logger` docs · https://hexdocs.pm/logger/Logger.html · Accessed February 7, 2026
- [R8] Erlang/OTP `ets` docs · https://www.erlang.org/doc/apps/stdlib/ets.html · Accessed February 7, 2026
- [R9] Erlang/OTP `persistent_term` docs · https://www.erlang.org/doc/apps/erts/persistent_term.html · Accessed February 7, 2026
- [R10] Erlang/OTP `erlang:process_info/2` docs · https://www.erlang.org/doc/apps/erts/erlang.html#process_info-2 · Accessed February 7, 2026
