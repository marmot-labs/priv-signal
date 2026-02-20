# Privacy-Relevant Data (PRD) Ontology v1 — FDD

## 1. Executive Summary
This design introduces an inventory-first PRD architecture where `priv-signal.yml` is the authoritative source of privacy-relevant data nodes and scan logic discovers evidence and flows for those nodes. It affects CLI users, CI maintainers, and privacy reviewers by replacing PII-only semantics with a five-class ontology while preserving deterministic artifact generation. The implementation reuses existing scan and infer runtime topology (`PrivSignal.Scan.Runner`, `PrivSignal.Infer.Runner`, `mix priv_signal.scan`, `mix priv_signal.diff`) and extends current config and artifact contracts rather than introducing a new service or redesigning runtime behavior. OTP alignment remains command-scoped and failure-isolated: bounded task parallelism, per-file error isolation, no long-lived bottleneck process, and strict determinism at reduction/output stages. The contracts are v1-only because this software has not been released. Performance posture targets existing CI behavior by retaining concurrency caps, immutable shared inventory, single-pass AST scanning, and canonical stable sorting/hashing. Security posture is unchanged for auth surface (local CLI), and privacy handling is strengthened by prohibition on emitting raw values from source code evidence. Headline risks are schema drift and noisy heuristics; mitigations are fail-fast v1 schema validation and deterministic matching rules. This design does not include any inventory proposal mechanism beyond explicit YAML definitions.

## 2. Requirements & Assumptions
### Functional Requirements
- FR-001: Define and enforce exactly five PRD classes.
- FR-002: Treat YAML inventory as authoritative for `data_nodes`.
- FR-003: Classify inventory entries deterministically into PRD classes.
- FR-004: Use static AST analysis to find usage evidence and flows for inventory entries.
- FR-005: Do not auto-add newly discovered code fields into authoritative inventory.
- FR-006: Emit deterministic lockfile output with inventory-backed nodes and observed flows.
- FR-007: Preserve byte-stable output for unchanged inputs.
- FR-008: Emit semantic triggers for inferred attributes, behavioral persistence, external export, and sensitive linkage.
- FR-009: Require v1-only YAML/artifact schemas.
- FR-010: Fail fast on any input that does not conform to v1 schema.
- FR-011: Provide reviewer-facing evidence/confidence metadata.
- FR-012: Preserve diff-based static architecture (no runtime instrumentation requirement).
- FR-013: Preserve existing scan/diff command workflow while extending identifier type handling and reporting semantics.

### Non-Functional Requirements
- Scan latency target: p50 <= 8s, p95 <= 20s on reference repos.
- Diff latency target: p50 <= 2s, p95 <= 5s on typical PR artifacts.
- Throughput target: >= 20 sequential CI runs/hour per worker without >10% memory growth.
- Memory target: <= 1.5x current scan baseline.
- Reliability target: >= 99% successful runs for valid config/input.
- Determinism target: repeated runs on same commit produce byte-identical lockfiles.

### Explicit Assumptions
- A1: Inventory entries are only those explicitly declared in YAML; entries are never inferred or proposed by this feature.
Impact: keeps scope narrow and deterministic.
- A2: `mix priv_signal.scan` remains the primary command surface and continues using infer-backed artifact generation.
Impact: no new runtime service is required.
- A3: Multi-tenant and LTI constraints are non-operative in this CLI-only repository context.
Impact: tenancy boundary is repository path and CI workspace.
- A4: No DB persistence is introduced.
Impact: no database schema changes.
- A5: Existing scanner family remains AST-static and best-effort.
Impact: false positives are managed through evidence confidence and deterministic matching rules.

## 3. Torus Context Summary
### What I know
- Config parsing/validation is centralized in `PrivSignal.Config.Loader` and `PrivSignal.Config.Schema`.
- Config model is PRD-shaped (`config.prd_nodes`) in `lib/priv_signal/config.ex` and inventory building uses `PrivSignal.Scan.Inventory.build/1`.
- Scan runtime uses bounded task concurrency via `Task.Supervisor.async_stream_nolink/6` in `PrivSignal.Scan.Runner` with timeout and per-file error isolation.
- Lockfile command path is `mix priv_signal.scan` and currently delegates to `PrivSignal.Infer.Runner`.
- Infer contract exists in `PrivSignal.Infer.Contract`; this feature documentation defines v1-only schema/contracts.
- Diff semantics exist in `PrivSignal.Diff.Semantic`, `PrivSignal.Diff.SemanticV2`, and `PrivSignal.Diff.ContractV2`.

### What I don’t know
- None blocking for v1 implementation.

### Runtime topology and boundaries
- Deployment is CLI process per invocation, typically in CI.
- State is in-memory per run and artifact output is file-based.
- Supervision is ephemeral and command-scoped, not a long-lived OTP app tree.
- Tenant boundary is repository; no cross-tenant shared runtime state.

## 4. Proposed Design
### 4.1 Component Roles & Interactions
- `PrivSignal.Config.Schema`: enforce PRD inventory schema validation for authoritative node definitions under v1 rules.
- `PrivSignal.Config`: introduce PRD structs (`PRDNode`, optional `PRDScope`) and parsing into typed config.
- `PrivSignal.Scan.Inventory`: build normalized PRD inventory indexes by node key, token, module, and class.
- Scanner modules (`Scan.Scanner.*`): continue extracting AST candidates with module/function/file/evidence context.
- `PrivSignal.Scan.Classifier`: shift classification from "candidate-is-PII" to "candidate matches YAML node scope/reference" and attach class/sensitivity from inventory.
- `PrivSignal.Infer.ScannerAdapter.Logging` and sibling adapters: map matched findings to canonical infer nodes with class metadata.
- `PrivSignal.Infer.FlowBuilder`: retain flow inference, extended to include PRD class-aware trigger hints.
- `PrivSignal.Infer.Output.JSON`: emit v1 lockfile with authoritative nodes and observed flows.
- `PrivSignal.Diff.Semantic*`: add PRD-aware change interpretation rules while preserving deterministic event IDs.
- `Mix.Tasks.PrivSignal.Scan` and `Mix.Tasks.PrivSignal.Diff`: preserve existing command workflow while surfacing expanded identifier classes in outputs.

Interaction sequence:
1. Load/validate YAML PRD inventory.
2. Build normalized inventory indexes.
3. Enumerate files and run scanners in bounded parallel tasks.
4. Match findings to inventory entries and create canonical nodes.
5. Build observed flows from grouped nodes.
6. Serialize lockfile deterministically.
7. Diff base/candidate artifacts to emit trigger events.

### 4.2 State & Message Flow
- Authoritative state owner: parsed config inventory (`PrivSignal.Config` struct).
- Derived state owner: inventory indexes (`PrivSignal.Scan.Inventory`).
- Worker-local state: AST parse tree, file scanner cache, raw candidates.
- Reducer state: merged findings/errors, canonical nodes/flows, summary counters.
- Backpressure point: `Task.Supervisor.async_stream_nolink/6` with capped concurrency and bounded timeout.
- Mailbox control: ordered streaming disabled and deterministic sorting performed post-reduction.
- Any AST-discovered fields not declared in YAML are treated as non-inventory evidence only and cannot create new authoritative nodes.

### 4.3 Supervision & Lifecycle
- Continue command-scoped temporary supervisor for scan workers.
- Use process-per-file units for failure isolation.
- Keep strict mode semantics: file-level errors become command failure only when strict flag is set.
- Keep no persistent GenServer for global state ownership to avoid bottlenecks.
- Ensure timeout kill policy remains `on_timeout: :kill_task`.

### 4.4 Alternatives Considered
- Alternative A: Auto-discover PRD nodes directly from code and treat them as authoritative.
Why not chosen: violates inventory-first requirement and increases noise/scope.
- Alternative B: Persist inventory and evidence in Postgres.
Why not chosen: unnecessary operational complexity for CLI artifact workflow.
- Alternative C: One centralized GenServer pipeline for all scanning.
Why not chosen: creates mailbox/bottleneck risk with no functional benefit.
- Recommended approach: YAML-authoritative inventory + bounded parallel AST evidence discovery + deterministic contract serialization.

## 5. Interfaces
### 5.1 HTTP/JSON APIs
- No HTTP API changes.
- Lockfile JSON contract is v1-only:
- `data_nodes` (authoritative inventory-backed nodes).
- `flows` (observed sink-bound paths tied to inventory references).
- Input validation errors remain CLI text output plus non-zero exit in failing paths.

### 5.2 LiveView
- No LiveView/UI changes in scope.
- If a UI consumer is added later, consume v1 lockfile only and never infer authority outside YAML.

### 5.3 Processes
- Process model remains `Task.Supervisor` worker fanout.
- No Registry/GenStage/Broadway required for v1 workload.
- Optional future scale extension: partition file list by hash bucket and run multiple supervisors per partition.

## 6. Data Model & Storage
### 6.1 Ecto Schemas
- No Ecto/Postgres schema changes in this repository.
- YAML schema changes in `PrivSignal.Config.Schema`:
- Require `version: 1` for PRD ontology mode.
- Replace `pii` list with `prd_nodes` list.
- `prd_nodes[]` required keys: `key`, `label`, `class`, `sensitive`, `scope`.
- `scope` supports exact module/field and optional pattern/module-glob variants.
- Enforce class enum to five allowed values.
- Enforce deterministic key uniqueness by `key`.

### 6.2 Query Performance
- No SQL query path.
- Matching path complexity:
- Build indexes O(n) over inventory size.
- Candidate matching O(1) average for token/module keyed lookups.
- Final deterministic sort O(m log m) for `m` nodes/flows.
- Expected hotspot is AST parse/traversal; preserve scanner cache usage and concurrency cap.

## 7. Consistency & Transactions
- Consistency model is deterministic per run; no distributed transactions.
- Phase boundaries:
1. Config validation must pass before scanning.
2. Scanning can partially fail per file without corrupting successful results.
3. Node/flow normalization runs only after candidate collection.
- Idempotency: same repo + config + tool version must produce identical artifact bytes.
- Retry policy: keep parse/read retries bounded and deterministic; no infinite retries.
- Compensation: partial file failures are recorded in `errors` and included in summary.

## 8. Caching Strategy
- Layer 1: in-memory immutable inventory index maps for tokens/modules/classes.
- Layer 2: existing AST scanner cache per file (`PrivSignal.Scan.Scanner.Cache`).
- No cross-run persistent caches in v1.
- Avoid `persistent_term` for frequently changing scan data to prevent global GC side effects.
- ETS is optional for large inventories; default path should stay map-based to reduce process coordination overhead.
- Multi-node coherence is not required in command-scoped CLI topology.

## 9. Performance and Scalability Plan
### 9.1 Budgets
- Scan p50 <= 8s, p95 <= 20s.
- Diff p50 <= 2s, p95 <= 5s.
- Max worker concurrency default: `min(System.schedulers_online(), 8)`.
- Peak memory <= 1.5x current baseline.
- Artifact size guardrail: cap evidence entries per node/flow to prevent large lockfiles.

### 9.2 Hotspots & Mitigations
- Hotspot: AST traversal cost in very large repos.
Mitigation: retain bounded concurrency and scanner cache.
- Hotspot: false positives from broad token matching.
Mitigation: scope-aware matching (module + field + class), confidence annotations.
- Hotspot: determinism drift due to unordered maps.
Mitigation: normalize and stable sort nodes/flows/events before serialization.
- Hotspot: mailbox growth under slow reducer.
Mitigation: consume stream continuously and avoid downstream synchronous blocking in reducer loop.

## 10. Failure Modes & Resilience
- Invalid PRD YAML schema: fail fast, no lockfile write.
- Non-v1 YAML/schema input: fail with explicit v1-only schema error.
- File parse failure: record error and continue unless strict mode.
- Worker timeout: kill worker, increment timeout metric, continue.
- Lockfile write failure: fail command after summary/logging.
- Diff contract mismatch: fail diff run with explicit contract error.

## 11. Observability
No additional observability, telemetry, or AppSignal reporting work is required for this feature.

## 12. Security & Privacy
- AuthN/AuthZ surface remains unchanged (local CLI/CI runner permissions).
- Inventory contains identifiers that may be sensitive; do not log raw inventory entries at info level.
- Evidence captured from AST must stay structural (module/function/line/type), not runtime value content.
- Repository-scoped execution naturally enforces tenant isolation in this codebase.
- Add audit-friendly log fields: command, schema_v1, strict_mode, outcome.

## 13. Testing Strategy
- Unit tests:
- PRD schema validation for `version: 1`, enum constraints, duplicate key rejection.
- Inventory index construction and deterministic normalization.
- Classifier matching semantics for module/field/pattern scopes.
- FlowBuilder and semantic trigger classification for PRD classes.
- Property tests:
- Stable sort/idempotent serialization for repeated identical input.
- Deterministic flow/event IDs independent of map insertion order.
- Integration tests:
- End-to-end `mix priv_signal.scan` on fixture repos covering all five classes.
- End-to-end `mix priv_signal.diff` verifying trigger emission types.
- Failure-path tests:
- Non-v1 YAML/schema rejection, parse timeout behavior, strict-mode failure, output write failures.
- Performance tests:
- Repeated benchmark runs to validate p50/p95 and memory guardrails.

## 15. Risks & Mitigations
- Risk: accidental schema drift away from v1 before release.
Mitigation: strict validator errors and explicit v1-only documentation.
- Risk: scanner misses scoped inventory references in metaprogrammed code.
Mitigation: keep confidence model and add explicit per-scanner module overrides.
- Risk: trigger noise from broad heuristics.
Mitigation: inventory authority + scope matching + deterministic thresholds.
- Risk: CI duration regressions.
Mitigation: preserve concurrency cap and cache AST context.

## 16. Open Questions & Follow-ups
- Decide whether any schema version beyond v1 is needed after explicit release declaration.

## 17. References
- Elixir `Task.Supervisor.async_stream_nolink/6` · https://hexdocs.pm/elixir/Task.Supervisor.html#async_stream_nolink/6 · Accessed 2026-02-20
- Elixir `Task.async_stream/3` semantics and concurrency controls · https://hexdocs.pm/elixir/Task.html#async_stream/3 · Accessed 2026-02-20
- Erlang/OTP `persistent_term` caveats · https://www.erlang.org/doc/apps/erts/persistent_term.html · Accessed 2026-02-20
- Erlang/OTP ETS user guide · https://www.erlang.org/doc/apps/stdlib/ets.html · Accessed 2026-02-20
- Phoenix PubSub docs · https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html · Accessed 2026-02-20
