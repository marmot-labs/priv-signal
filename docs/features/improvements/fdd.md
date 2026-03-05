# PrivSignal Scanner Recall & Explainability Improvements — FDD

## 1. Executive Summary
This design improves PrivSignal scanner recall for realistic code patterns that appeared in staged pull-request validation, while preserving deterministic behavior and explainability. It targets three concrete gaps: literal-only PRD token matching, direct-callsite-only DB sink detection, and HTTP payload detection that fails when data is prebuilt before the sink call. The implementation introduces controlled normalization and alias matching, wrapper-aware DB sink inference through intra-module summaries, and intra-function HTTP provenance tracing. The design keeps analysis static, local, and bounded to AST semantics already used by PrivSignal, avoiding dynamic runtime tracing or full call-graph analysis. Confidence is expanded from binary to staged tiers (`confirmed`, `probable`, `possible`) so increased recall does not collapse precision into opaque heuristics. Changes are intentionally incremental and scoped to existing scanner modules to minimize operational risk. Determinism is maintained through stable traversal order, stable summary construction, and stable result sorting/fingerprints. Failure behavior remains best-effort per file: parse/provenance errors degrade to baseline scanner behavior without crashing a run. This design affects CLI scan/diff/score artifact quality and reviewer trust, not application runtime request paths. Primary risks are false-positive drift from normalization/alias breadth and complexity growth in HTTP provenance; both are constrained by configuration guardrails, confidence tiering, and strict fixture-based unit coverage.

## 2. Requirements & Assumptions
### Functional Requirements
- `FR-001` to `FR-003`: add normalized + alias PRD matching with explicit confidence source.
- `FR-004` to `FR-006`: add wrapper-aware DB sink detection via config and deterministic intra-module summaries.
- `FR-007` and `FR-008`: add intra-function HTTP payload provenance and `indirect_payload_ref` evidence.
- `FR-009`: expose staged confidence model (`confirmed`, `probable`, `possible`).
- `FR-010`: preserve deterministic, backward-compatible output contracts where feasible.
- `FR-011`: add fixture-based regression coverage for all three limitation classes.

### Non-Functional Requirements
- Runtime overhead target: p50 scan duration increase <= 15%, p95 <= 25%, memory <= 20% increase vs baseline fixtures.
- Determinism target: identical code/config inputs produce byte-stable ordered findings and stable IDs.
- Resilience target: analysis failures are file-local and do not terminate whole scans.
- Explainability target: every non-exact match includes explicit confidence source and evidence chain.

### Explicit Assumptions
- Analysis remains static over Elixir AST (`.ex`/`.exs`) and does not execute code.
- Initial wrapper inference is intra-module only; inter-module call graph is out of scope.
- Alias maps are repository-maintained and intentionally curated (no auto-generated synonym expansion).
- HTTP provenance pass is intra-function only, with bounded supported builders (map/keyword literals, `Map.put`, `Map.merge`, `Jason.encode!`).
- No new persistent storage is introduced; all state is per-run memory.

## 3. Repository Context Summary
PrivSignal runs as a CLI analyzer in CI against repository diffs and produces findings consumed by reviewers and scoring logic. The relevant internal boundaries are scanner inventory/evidence extraction (`PrivSignal.Scan.Inventory`, `PrivSignal.Scan.Scanner.Evidence`), sink scanners (`Database`, `HTTP`), runner orchestration (`PrivSignal.Scan.Runner`), and downstream classification/output (`Classifier`, JSON/Markdown output modules).

### What I know
- Scanner execution is already bounded and parallelized by file using `Task.Supervisor.async_stream_nolink` with deterministic result ordering.
- Token evidence today is primarily literal and callsite-local, which explains staged misses.
- DB scanner currently keys off direct `Repo.*` methods; wrapper indirection is not inferred.
- HTTP scanner requires PRD evidence in sink-call argument AST; prebuilt payload variables can lose linkage.
- Config schema is strict and centralized, suitable for adding explicit alias/wrapper controls.

### What I do not know
- `./guides/design/**/*.md` was not present in this repository, so no additional local architecture guidance was available from that path.
- Precise baseline performance envelope for very large monorepos (>10k Elixir files) is not currently documented in-repo.
- Expected long-term compatibility policy for downstream consumers of finding JSON fields needs confirmation.

## 4. Proposed Design
### 4.1 Component Roles & Interactions
- `PrivSignal.Scan.Scanner.Evidence`
- Add normalization pipeline for candidate identifiers before PRD lookup.
- Emit evidence with `match_source` metadata: `exact`, `normalized`, `alias`.
- Defer confidence tier mapping to classifier to keep scanner modules composable.

- `PrivSignal.Scan.Inventory`
- Build normalized token index and alias index from config.
- Maintain deterministic canonical mapping from normalized candidate -> PRD token(s).
- Validate alias collisions early to prevent ambiguous mappings.

- `PrivSignal.Scan.Scanner.Database`
- Keep existing direct `Repo.*` detection.
- Add wrapper-aware detection path fed by intra-module function summaries.
- Emit inherited sink evidence when callsite targets summarized wrapper functions.

- `PrivSignal.Scan.Scanner.HTTP`
- Add intra-function provenance graph builder for variable lineage.
- Resolve sink args through lineage graph.
- Emit new evidence type `indirect_payload_ref` with variable chain path.

- `PrivSignal.Scan.Classifier`
- Replace binary confidence mapping with staged confidence model.
- Confidence derivation inputs: direct AST evidence, normalized/alias evidence, provenance-only evidence.

- `PrivSignal.Config` and `PrivSignal.Config.Schema`
- Add config keys for aliases and DB wrappers.
- Validate shape/types and reject ambiguous or invalid entries with actionable errors.

### 4.2 State & Message Flow
- Runner loads config and builds immutable inventory indexes (exact, normalized, alias).
- File workers parse AST and run sink scanners as today.
- Each scanner pass emits findings with evidence atoms and structured metadata.
- DB scanner requests module-local summary from cached AST helper; summary is deterministic and memoized per file/module.
- HTTP scanner builds function-local provenance map during traversal and resolves sink argument variables at emission time.
- Classifier maps evidence bundle -> confidence tier.
- Runner aggregates, dedupes, sorts, and emits JSON/Markdown artifacts.

Backpressure and bounds:
- Existing bounded file parallelism remains unchanged.
- Provenance/summaries are intra-file and not retained globally beyond run scope.
- No unbounded mailbox fan-out is introduced.

### 4.3 Supervision & Lifecycle
- No long-lived OTP tree change is required.
- Existing short-lived task supervision model remains the execution boundary.
- Worker crashes/timeouts remain isolated and surfaced as file-scoped errors.
- New analyses run inside existing per-file worker lifecycle, preserving failure containment.

### 4.4 Alternatives Considered
- Full-project call graph for wrapper and provenance inference.
- Rejected for this phase due to complexity, non-trivial determinism risk, and higher runtime cost.

- Generic fuzzy string similarity for PRD matching.
- Rejected due to explainability/precision risks and poor reviewer auditability.

- Runtime taint instrumentation.
- Rejected because PrivSignal is designed as static CI analysis and should remain build-system agnostic.

Chosen approach: deterministic, config-controlled static inference with staged confidence output.

## 5. Interfaces
### 5.1 CLI and Output Contracts
- Commands unchanged: `mix priv_signal.scan`, `mix priv_signal.diff`, `mix priv_signal.score`.
- Finding contract additions:
- `confidence` supports `confirmed`, `probable`, `possible`.
- Evidence item supports `match_source` and `indirect_payload_ref` lineage payload.
- Backward compatibility:
- Keep existing fields where possible.
- Additive fields are optional for downstream parsers.

### 5.2 Configuration (`priv-signal.yml`)
Proposed additions:
- `matching.aliases`: map of alias token -> canonical PRD token.
- `matching.normalization`: options for split/singularize/prefix stripping.
- `scanners.database.wrapper_modules`: list of modules treated as wrapper candidates.
- `scanners.database.wrapper_functions`: optional allowlist of function names/arity patterns.
- `strict_exact_only`: optional mode to disable normalized/alias/provenance for precision comparison rollout.

Validation rules:
- Alias keys/values must normalize to non-empty tokens.
- Alias targets must exist in declared PRD inventory.
- Wrapper module/function entries must be syntactically valid and deduplicated.

### 5.3 Process Interfaces
- No new GenServer/Registry interface is required.
- Reuse existing scanner cache helper for per-file memoization of summaries/provenance helpers.

## 6. Data Model & Storage
No Postgres/Ecto schema changes are required.

In-memory structures to add:
- `normalized_token_index`: `%{normalized_token => MapSet[canonical_token]}`
- `alias_index`: `%{alias_token => canonical_token}`
- `module_function_summary`: `%{{module, function, arity} => %{db_read?: boolean, db_write?: boolean}}`
- `provenance_graph`: `%{var_name => %{sources: [...], builders: [...], prd_refs: [...]}}`

Determinism rules:
- Construct maps from sorted traversals where order affects output.
- Normalize strings with pure deterministic transforms only.
- Sort evidence chains before serialization.

## 7. Consistency & Transactions
- Scanner run consistency is strong per invocation: immutable config + source tree snapshot yields deterministic output.
- No external transactions exist; consistency boundary is in-memory analysis pipeline.
- Idempotency guaranteed by deterministic traversal + stable sorting + deterministic fingerprinting.
- Degradation policy: if provenance resolution fails for a sink, scanner falls back to direct sink-arg evidence path without crashing.

## 8. Caching Strategy
- Keep existing per-file scanner cache behavior; extend cache payload with:
- function DB summaries
- optional precomputed normalization artifacts per module

Invalidation:
- Cache is run-scoped and discarded at process end, so no cross-run invalidation complexity.

Rationale:
- Avoid `persistent_term` for frequently changing scanner data due global update costs.
- Avoid cross-run ETS persistence to preserve simplicity/determinism.

## 9. Performance & Scalability Plan
### 9.1 Budgets
- Additional normalization pass should be O(token_count) per file and near-constant memory overhead.
- DB summary extraction should be O(function_count + Repo callsite count) per file.
- HTTP provenance should be O(AST nodes in function) with explicit guardrails on tracked builder depth.

### 9.2 Hotspots & Mitigations
- Hotspot: large functions with heavy map transformations.
- Mitigation: bounded provenance depth and supported-builder whitelist.

- Hotspot: alias explosions from oversized config maps.
- Mitigation: schema limits and deterministic conflict rejection.

- Hotspot: duplicate evidence inflation.
- Mitigation: canonical evidence normalization and dedupe by deterministic fingerprint.

## 10. Failure Modes & Resilience
- Invalid alias/wrapper config:
- fail fast at config validation with precise path-based error messages.

- Unparseable file:
- retain existing behavior; record file-level analysis error and continue.

- Provenance builder unsupported pattern:
- emit lower-confidence path when direct evidence exists; otherwise no speculative finding.

- Timeout in worker task:
- preserve existing timeout semantics and isolate failure to that file unit.

## 11. Observability
The PRD scope explicitly removes telemetry requirements.

Design posture:
- no new mandatory telemetry events, dashboards, or alerts.
- preserve current structured scanner output for debugging and regression comparison.
- if optional debug logging is added later, it must avoid runtime data values and remain disabled by default.

## 12. Security & Privacy
- Alias and normalization logic should not surface runtime payload values; only token identifiers and AST lineage.
- Confidence tiers must not imply certainty of real data movement beyond static evidence.
- Config changes that broaden matching are auditable in version control.
- Tenant/runtime boundaries in analyzed applications are unaffected because analysis occurs on source code artifacts only.

## 13. Testing Strategy
Unit-test focused only, per PRD constraints.

Required test groups:
- normalization/alias matching matrix:
- exact vs normalized vs alias outcomes
- singularization/case-split/prefix-strip edge cases
- deterministic tie-break behavior when multiple canonical tokens compete

- DB wrapper summaries:
- direct `Repo.*` baseline unchanged
- intra-module wrapper inference positive/negative cases
- wrapper config allowlist/blocklist behavior

- HTTP provenance:
- variable assignment chains
- map/keyword literal propagation
- `Map.put`, `Map.merge`, `Jason.encode!` propagation
- unsupported transform fallbacks

- confidence model:
- direct evidence -> `confirmed`
- normalized/alias/provenance without direct -> `probable`
- weak heuristic-only -> `possible`

- end-to-end fixture pair:
- one fixture pair demonstrating previously unreachable evidence shapes now emitted and scored.

- determinism:
- repeated runs on same fixture produce byte-identical sorted findings.

## 14. Risks & Mitigations
- Risk: false positives increase due to normalization and aliases.
- Mitigation: config-gated aliases, confidence tiering, strict exact-only comparison mode.

- Risk: provenance complexity affects runtime on large files.
- Mitigation: bounded builder set, bounded depth, per-file caching, early exits.

- Risk: JSON contract drift affects downstream consumers.
- Mitigation: additive fields only, preserve existing keys, version notes in docs.

- Risk: wrapper inference misses inter-module helpers.
- Mitigation: explicitly document phase-1 intra-module scope and capture follow-up backlog.

## 15. Open Questions & Follow-ups
- Should confidence source (`exact`/`normalized`/`alias`/`provenance`) be modeled as a separate field from confidence tier for downstream scoring flexibility?
- Should alias mapping support one-to-many canonical targets, or remain strictly one-to-one for explainability?
- Should provenance include function call boundaries for known pure helper functions in phase 2?
- What hard limits should be enforced for alias map size and provenance chain length?

## 16. Implementation Plan (Architectural Sequencing)
- Phase 1: config + normalization/alias index and evidence metadata.
- Phase 2: DB wrapper config + intra-module summary inference.
- Phase 3: HTTP provenance graph and `indirect_payload_ref` emission.
- Phase 4: confidence harmonization, output/docs alignment, deterministic regression fixtures.

## 17. References
- Elixir `Task.Supervisor` docs · https://hexdocs.pm/elixir/Task.Supervisor.html · Accessed 2026-03-04
- Elixir `Macro` docs · https://hexdocs.pm/elixir/Macro.html · Accessed 2026-03-04
- Erlang/OTP Design Principles (Supervision) · https://www.erlang.org/docs/24/design_principles/sup_princ · Accessed 2026-03-04
- Erlang ETS docs · https://www.erlang.org/doc/apps/stdlib/ets.html · Accessed 2026-03-04
- Erlang `persistent_term` docs · https://www.erlang.org/doc/apps/erts/persistent_term.html · Accessed 2026-03-04
- Ecto `Ecto.Changeset` docs · https://hexdocs.pm/ecto/Ecto.Changeset.html · Accessed 2026-03-04
- Ecto `Ecto.Multi` docs · https://hexdocs.pm/ecto/Ecto.Multi.html · Accessed 2026-03-04
- PostgreSQL EXPLAIN docs · https://www.postgresql.org/docs/current/using-explain.html · Accessed 2026-03-04
