# FDD: PrivSignal Phase 4 Sinks and Sources Expansion

## 1. Executive Summary
Phase 4 expands PrivSignal from logging-centric detection to five deterministic scanner categories: HTTP outbound sinks, controller response sinks, telemetry sinks, database read/write source-sink nodes, and LiveView exposure sinks. The design keeps the existing runtime model: short-lived Mix task execution with bounded parallel file workers, no long-lived scanner service, and no interprocedural taint analysis. The implementation is additive to the current `PrivSignal.Scan.Runner` and `PrivSignal.Infer.Runner` pipeline, with proto-flow v1 logic unchanged and only node coverage expanded. We introduce category-aware scanner modules under `PrivSignal.Scan.Scanner.*`, aggregate their findings in one per-file AST traversal, and normalize findings into infer nodes via a unified adapter path. Configuration is extended with `scanners.*` category toggles and overrides while preserving backward compatibility for existing configs by defaulting missing scanner config to enabled defaults. Determinism is preserved by stable sorting, canonical path/module normalization, and existing `NodeIdentity` hashing semantics. Failure isolation remains file-scoped through `Task.Supervisor.async_stream_nolink/6` with timeout handling and strict-mode escalation unchanged. Performance posture targets at most 20% p95 regression from current scan baseline by avoiding repeated AST traversal and by caching per-file module classification and alias resolution. The highest risks are false-positive inflation and boundary misclassification; mitigation is confidence scoring, explicit evidence signals, and conservative external-boundary defaults with config overrides. This design affects engineering and privacy review workflows directly but does not alter deployment topology, tenancy model, or persistence infrastructure.

## 2. Requirements & Assumptions
### Functional Requirements
- `FR-001` Add multi-category deterministic scanning in one file pass and aggregate normalized findings.
- `FR-002` Detect outbound HTTP client calls and emit sink nodes with `role.kind="http"`, subtype, boundary, confidence, and evidence.
- `FR-003` Detect controller response exposure calls and emit sink nodes with `role.kind="http_response"`.
- `FR-004` Detect telemetry and analytics export calls and emit sink nodes with `role.kind="telemetry"`.
- `FR-005` Detect DB reads as source nodes and DB writes as sink nodes for configured repo modules.
- `FR-006` Detect LiveView exposure patterns and emit sink nodes with `role.kind="liveview_render"`.
- `FR-007` Add `scanners` YAML schema with per-category enablement and overrides.
- `FR-008` Preserve stable node identity and normalized code context.
- `FR-009` Keep proto-flow build logic unchanged while allowing new node roles to participate.
- `FR-010` Add category-level telemetry and summary counters for scan/infer health.
- `FR-011` Preserve compatibility for repos without explicit `scanners` config.

### Non-Functional Requirements
- Determinism: repeated runs on identical inputs produce byte-stable findings and node IDs.
- Performance: p95 full scan wall-clock regression <= 20% vs current logging-only baseline.
- Reliability: per-file parser or timeout failures do not abort non-strict runs.
- Security: no runtime execution, no external calls, no value-level PII emission in telemetry/output.
- Observability: category-level timings, counts, and error metrics wired to AppSignal via telemetry.

### Explicit Assumptions
- Assumption: `docs/prd.md`, `docs/fdd.md`, and `docs/plan.md` do not exist in this repository root.
- Impact: architecture context is derived from feature docs and code reconnaissance only.
- Assumption: `mix priv_signal.scan` remains a lockfile-producing command and still routes through infer output (`PrivSignal.Infer.Runner`).
- Impact: scanner output shape changes must preserve infer artifact compatibility (`schema_version 1.2`).
- Assumption: boundary inference for HTTP hosts can be static-literal first in Phase 4.
- Impact: dynamic URL expressions default to external with reduced confidence.

## 3. Torus Context Summary
### What I know
- Entry point: `Mix.Tasks.PrivSignal.Scan` currently loads config then calls `PrivSignal.Infer.Runner.run/2` and writes infer JSON/Markdown.
- Scan runtime: `PrivSignal.Scan.Runner` already supports bounded concurrency, timeout handling, strict mode, and telemetry emission.
- Current scanner: `PrivSignal.Scan.Logger` is logging-only and produces candidate findings with evidence extracted from AST.
- Finding classification: `PrivSignal.Scan.Classifier` derives `confirmed_pii` vs `possible_pii`, sensitivity, and deterministic finding ID.
- Infer adaptation: `PrivSignal.Infer.ScannerAdapter.Logging` converts findings to nodes with normalized context and stable IDs.
- Flow builder: `PrivSignal.Infer.FlowBuilder` groups nodes by module/function/file and computes flows from source references to sink nodes.
- Configuration: `PrivSignal.Config.Schema` validates `version`, `pii`, and `flows`; no `scanners` section exists yet.
- Telemetry: unified wrapper `PrivSignal.Telemetry.emit/3` already used in scan and infer pipelines.

### What I do not know
- Exact downstream consumers of infer sink kind values beyond current flow scoring.
- Required backward-compatibility guarantees for third-party parsers of lockfile JSON fields beyond current tests.
- Preferred policy for `external_domains` vs `internal_domains` conflict precedence.

### Runtime topology and tenancy
- Single-node CLI execution in local dev or CI.
- No cross-tenant runtime state; repository config is the tenancy boundary.
- No persistent worker process; work is ephemeral and task-supervised.

## 4. Proposed Design
### 4.1 Component Roles & Interactions
- `PrivSignal.Config`:
  Add `scanners` struct subtree with defaults and category overrides.
- `PrivSignal.Config.Schema`:
  Validate `scanners` additive schema and allow omission by injecting defaults.
- `PrivSignal.Scan.Scanner` behavior:
  Define callback `scan_ast(ast, file_ctx, inventory, scanner_cfg) :: [candidate]`.
- `PrivSignal.Scan.Scanner.Logging`:
  Move existing logging logic from `PrivSignal.Scan.Logger` with behavior compliance.
- `PrivSignal.Scan.Scanner.HTTP`:
  Detect outbound HTTP client and wrapper patterns; compute boundary and confidence.
- `PrivSignal.Scan.Scanner.Controller`:
  Detect response exposure calls and configured render helpers.
- `PrivSignal.Scan.Scanner.Telemetry`:
  Detect telemetry/export SDK calls and configured observability wrappers.
- `PrivSignal.Scan.Scanner.Database`:
  Detect repo read/write calls and emit `node_type` source/sink candidates.
- `PrivSignal.Scan.Scanner.LiveView`:
  Detect assign/render/push_event exposure points in LiveView modules/components.
- `PrivSignal.Scan.Runner`:
  Parse each file once, run enabled scanner modules on shared AST, aggregate and classify.
- `PrivSignal.Infer.ScannerAdapter`:
  Replace logging-specific adapter with a generic adapter mapping candidate role/node-type to infer nodes.
- `PrivSignal.Infer.FlowBuilder`:
  Keep algorithm unchanged; extend `@external_sink_kinds` to include `telemetry`, `http_response`, and `liveview_render` boundary policies where required.

### 4.2 State & Message Flow
- Runner owns immutable scan inventory and resolved scanner configuration.
- Each file task owns parsed AST, alias/module context cache, and scanner-local accumulators.
- Message flow:
  `source file -> parse AST -> invoke enabled scanners (same AST) -> emit candidates -> classify -> adapt to nodes -> flow build`.
- Backpressure points:
  concurrency cap and timeout in `async_stream_nolink`; scanner modules must be pure and non-blocking.

### 4.3 Supervision & Lifecycle
- Keep transient supervisor startup inside `PrivSignal.Scan.Runner`.
- Worker failures remain isolated to file-level result tuples.
- Strict mode behavior remains unchanged: any worker error produces terminal failure after artifact emission.
- No new GenServer required; scanners remain pure functions to avoid bottleneck mailbox state.

### 4.4 Alternatives Considered
- Alternative: separate AST traversal per category scanner.
- Rejected: simple implementation but avoidable CPU overhead and p95 regression risk.
- Alternative: centralized GenServer with scanner registry and mutable state.
- Rejected: unnecessary serialization bottleneck and restart coupling.
- Alternative: compile-time instrumentation or BEAM introspection.
- Rejected: weaker source-line evidence and harder deterministic parity for modified working trees.
- Recommended: one AST parse per file, pure scanner modules, reducer-based aggregation.

## 5. Interfaces
### 5.1 HTTP/JSON APIs
- External network API: none.
- Artifact contract changes are additive.
- Scan/infer JSON keeps existing top-level keys; node `role.kind` and `role.callee` gain new category values.
- New config contract in `priv-signal.yml`:

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

### 5.2 LiveView
- No LiveView UI in PrivSignal itself.
- Scanner logic inspects host-app LiveView AST patterns only.

### 5.3 Processes
- No new long-lived processes.
- Existing `Task.Supervisor` worker pattern retained.
- No `Registry`, `GenStage`, or `Broadway` needed for this feature.

## 6. Data Model & Storage
### 6.1 Ecto Schemas
- No new database tables or migrations.
- Data model changes are in-memory structs/config schema only.
- Add `PrivSignal.Config.Scanners` and per-category nested structs for typed defaults/validation.
- Candidate finding structure must support:
  `node_type`, `role_kind`, `role_subtype`, `boundary`, `confidence`, `evidence`, location metadata, matched fields.

### 6.2 Query Performance
- No SQL query path.
- Core computational cost is AST traversal.
- Complexity target per file: `O(ast_nodes * enabled_scanner_count)` with scanner checks reduced via module/function dispatch tables.
- Expected execution profile: CPU-bound parsing and traversal, low IO, bounded memory by `max_concurrency`.

## 7. Consistency & Transactions
- Consistency model is deterministic functional reduction over immutable per-file results.
- No transactional DB writes.
- Idempotency guaranteed by stable sort keys and `NodeIdentity.id/2` hashing.
- Retry strategy is file-local via rerun; no stateful compensation needed.

## 8. Caching Strategy
- Keep cache scope per-file/per-run.
- Use plain maps for per-file alias and module-classification caches inside worker.
- Avoid `persistent_term` for scanner rules because update churn can trigger VM-wide GC impact.
- Do not introduce distributed cache; CLI runtime is single-node and ephemeral.

## 9. Performance and Scalability Plan
### 9.1 Budgets
- p50 scan runtime <= 5s on representative CI fixture set.
- p95 scan runtime <= current baseline * 1.20.
- Timeout default remains 5000ms per file task unless CLI override.
- Concurrency cap remains `min(System.schedulers_online(), 8)`.
- Peak memory target <= 1.25x current logging-only scan for same corpus.

### 9.2 Hotspots & Mitigations
- Hotspot: repeated matcher checks across scanners.
- Mitigation: precompute call dispatch lookup maps per category and short-circuit by module context.
- Hotspot: path/module normalization repeated in adapters.
- Mitigation: normalize once at candidate build and avoid duplicate string transformations.
- Hotspot: flow boundary classification misses new sink kinds.
- Mitigation: update external sink kind set and add unit coverage for each new role kind.
- Hotspot: mailbox accumulation under fast workers.
- Mitigation: keep bounded stream and avoid materializing raw ASTs in result payloads.

## 10. Failure Modes & Resilience
- Failure: parser error in one file.
- Handling: emit error item `{file, type: :parse_error}` and continue unless strict mode.
- Failure: worker timeout on very large/generated file.
- Handling: keep existing timeout kill behavior, emit timeout counter, support CLI override.
- Failure: malformed scanner config.
- Handling: fail fast during `Config.Schema.validate/1` with explicit key path.
- Failure: false-positive spike after rollout.
- Handling: category-level disable flags provide immediate kill switch without code rollback.

## 11. Observability
- New telemetry events:
  - `[:priv_signal, :scan, :category, :run]` measurements: `duration_ms`, `finding_count` metadata: `category`, `enabled`, `error_count`.
  - `[:priv_signal, :scan, :candidate, :emit]` measurements: `count` metadata: `node_type`, `role_kind`.
  - Keep existing `[:priv_signal, :scan, :run]` and `[:priv_signal, :infer, :flow, :build]` events.
- Metric cardinality guardrails:
  avoid file path/module in metric tags; use category and role enums only.
- AppSignal dashboards:
  scan duration p95, scan error rate, findings by category, strict-mode failure count.
- Alert thresholds:
  parse+timeout error rate > 2% files scanned for 3 consecutive CI windows.
  category finding count drops > 80% week-over-week for active repos.

## 12. Security & Privacy
- Scanner remains static-analysis-only; no runtime data reads.
- Evidence redaction policy: include AST symbols and code locations, never runtime payload contents.
- Tenant isolation: repository/config path is the boundary; no cross-repo state sharing.
- AuthN/AuthZ: inherited from repository/CI controls; no new service surface.
- Auditability: findings include deterministic IDs, location context, and rule/evidence signals.

## 13. Testing Strategy
- Unit tests per scanner module for positive and negative patterns.
- Config schema tests for `scanners` defaults, overrides, and invalid shape handling.
- Integration tests on mixed fixture repo verifying all five categories and deterministic outputs.
- Adapter contract tests for candidate -> node mapping and stable IDs.
- Flow regression tests confirming proto-flow algorithm unchanged with expanded node roles.
- Resilience tests for parse errors, timeouts, strict mode behavior.
- Performance regression test script in CI using fixed corpus and p95 comparison threshold.

## 14. Rollout and Backwards Compatibility
- Phase rollout:
  enable all categories by default in dev, canary in CI on selected repos, then full enable.
- Backward compatibility:
  missing `scanners` config maps to defaults; existing logging behavior remains.
- Kill switch:
  disable category via config without deploy.
- Rollback:
  revert config defaults to logging-only and keep infer schema unchanged.

## 15. Risks & Mitigations
- Risk: external boundary over-classification increases noise.
- Mitigation: host-domain overrides, confidence downgrades, and explicit evidence tags.
- Risk: infer flow semantics drift with new node roles.
- Mitigation: dedicated regression suite for flow counts and boundary distribution.
- Risk: performance regression from multi-category checks.
- Mitigation: one-pass AST traversal and dispatch table optimization.
- Risk: config complexity for repo owners.
- Mitigation: strict schema errors with examples and docs updates in `mix priv_signal.init` output.

## 16. Open Questions & Follow-ups
- Resolved (2026-02-15): `http.external_domains` overrides `http.internal_domains` on conflict.
- Resolved (2026-02-15): controller/liveview sinks require explicit PII field evidence before emission.
- Resolved (2026-02-15): telemetry calls with unknown destination default to `external` with lower confidence.
- Resolved (2026-02-15): `FlowBuilder` treats `http_response`, `liveview_render`, and `telemetry` sink kinds as `external`.

## 17. References
- Elixir `Task.Supervisor` docs · https://hexdocs.pm/elixir/Task.Supervisor.html · Accessed 2026-02-15
- Elixir `Task.async_stream/3` docs · https://hexdocs.pm/elixir/Task.html#async_stream/3 · Accessed 2026-02-15
- Telemetry README/docs · https://hexdocs.pm/telemetry/readme.html · Accessed 2026-02-15
- Erlang/OTP `persistent_term` docs · https://www.erlang.org/doc/apps/erts/persistent_term.html · Accessed 2026-02-15
- Erlang/OTP `ets` docs · https://www.erlang.org/doc/man/ets.html · Accessed 2026-02-15
- Phoenix LiveView docs · https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html · Accessed 2026-02-15
- Ecto `Ecto.Repo` docs · https://hexdocs.pm/ecto/Ecto.Repo.html · Accessed 2026-02-15
- Ecto query docs · https://hexdocs.pm/ecto/Ecto.Query.html · Accessed 2026-02-15
