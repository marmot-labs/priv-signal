# PrivSignal Architecture

PrivSignal is an Elixir Mix-task based CLI for detecting privacy drift in Elixir codebases. It turns a human-authored privacy catalog into deterministic scan artifacts, compares those artifacts across branches, and produces a PR-level privacy risk score.

The implementation is intentionally split into four major stages:

1. Configuration loading and validation.
2. Static scan and lockfile inference.
3. Semantic lockfile diffing.
4. Deterministic scoring.

The main runtime path used in CI is:

```text
priv_signal.yml
  -> mix priv_signal.validate
  -> mix priv_signal.scan
  -> priv_signal.lockfile.json
  -> mix priv_signal.diff --base <ref> --format json
  -> tmp/privacy_diff.json
  -> mix priv_signal.score --diff tmp/privacy_diff.json
  -> tmp/priv_signal_score.json
```

PrivSignal is advisory. It does not claim compliance, and its score is a review signal rather than a legal decision.

## Repository Layout

The implementation lives under `lib/`:

- `lib/mix/tasks/`: public CLI entrypoints exposed as Mix tasks.
- `lib/priv_signal/config*`: config structs, parsing, schema validation, and summaries.
- `lib/priv_signal/validate*`: source indexing and catalog validation.
- `lib/priv_signal/scan*`: AST scanners that find privacy-relevant usage in source code.
- `lib/priv_signal/infer*`: conversion from scan findings into lockfile nodes and flows.
- `lib/priv_signal/diff*`: lockfile artifact loading, normalization, semantic diffing, and rendering.
- `lib/priv_signal/score*`: deterministic scoring from v2 semantic diff events.
- `lib/priv_signal/llm*` and `lib/priv_signal/analysis*`: legacy and optional advisory LLM support.
- `lib/priv_signal/output*`: legacy output helpers retained for older analysis paths.
- `lib/priv_signal/runtime.ex` and `lib/priv_signal/telemetry.ex`: shared runtime and telemetry support.

User-facing documentation is split across:

- `README.md`: quick start, command usage, and contribution basics.
- `SCORING.md`: score semantics and reviewer-facing examples.
- `docs/classification_registry.md`: stable `PS-SCAN-*`, `PS-DIFF-*`, and `PS-SCORE-*` registry IDs.
- `docs/features/*`: feature PRDs, FDDs, plans, rollout notes, and traceability artifacts.

## Design Principles

PrivSignal’s implementation follows a few core constraints:

- The source of privacy intent is explicit configuration in `priv_signal.yml`.
- Generated artifacts are deterministic and suitable for version control.
- `diff` is analysis-only: it compares lockfiles and does not run inference.
- `score` is deterministic: optional LLM interpretation can add commentary, but cannot alter the score.
- Outputs are plain-text and JSON-friendly so they work locally, in CI, and in PR automation.

## CLI Entrypoints

Each public command is a Mix task.

### `mix priv_signal.init`

Implemented by `Mix.Tasks.PrivSignal.Init`.

This command writes a starter `priv_signal.yml` when one does not already exist. The sample config includes:

- `version: 1`
- `prd_nodes`
- scanner configuration for logging, HTTP, controller, telemetry, database, and LiveView categories

The initializer is intentionally simple: it does not inspect a project. The inventory bootstrap skill under `skills/priv-signal-inventory/` exists for AI-assisted catalog creation.

### `mix priv_signal.validate`

Implemented by `Mix.Tasks.PrivSignal.Validate`.

The validation task:

1. Starts runtime dependencies through `PrivSignal.Runtime.ensure_started/0`.
2. Loads `priv_signal.yml` through `PrivSignal.Config.Loader`.
3. Runs `PrivSignal.Validate.run/2`.
4. Formats results with `PrivSignal.Validate.Output`.
5. Raises if configured PRD node scopes do not validate.

Validation checks both schema shape and source correspondence. The schema layer verifies that `prd_nodes` are well-formed. The source validation layer checks that configured modules and fields can be found in the source index built by `PrivSignal.Validate.Index`.

### `mix priv_signal.scan`

Implemented by `Mix.Tasks.PrivSignal.Scan`.

The scan task is the artifact generation command. It:

1. Loads config.
2. Runs `PrivSignal.Infer.Runner`.
3. Renders Markdown and JSON through `PrivSignal.Infer.Output.*`.
4. Writes the lockfile JSON to `priv_signal.lockfile.json` by default.
5. Prints a short scan summary to the shell.

Supported options include:

- `--json-path PATH`
- `--strict`
- `--quiet`
- `--timeout-ms N`
- `--max-concurrency N`

Strict mode fails the command when scan errors occur. Non-strict mode still writes output with errors included in the result.

### `mix priv_signal.diff`

Implemented by `Mix.Tasks.PrivSignal.Diff`.

The diff task compares lockfile artifacts rather than raw source code. It accepts a base ref, plus either a workspace candidate lockfile or a candidate git ref. The command delegates option parsing to `PrivSignal.Diff.Options` and execution to `PrivSignal.Diff.Runner`.

The important design boundary is that `diff` never runs inference. If the candidate lockfile is missing or stale, the user must run `mix priv_signal.scan` before diffing.

### `mix priv_signal.score`

Implemented by `Mix.Tasks.PrivSignal.Score`.

The score task consumes v2 semantic diff JSON from `mix priv_signal.diff --format json`. It:

1. Loads config, primarily for scoring and optional advisory settings.
2. Loads and validates the diff artifact with `PrivSignal.Score.Input`.
3. Runs deterministic scoring through `PrivSignal.Score.Engine`.
4. Optionally runs `PrivSignal.Score.Advisory`.
5. Renders JSON through `PrivSignal.Score.Output.JSON`.
6. Writes the score artifact through `PrivSignal.Score.Output.Writer`.

The command requires `--diff <path>`. The default score output path is `priv_signal_score.json`.

## Configuration Model

`priv_signal.yml` is represented by `PrivSignal.Config`.

The top-level config struct contains:

- `version`
- `prd_nodes`
- `matching`
- `scanners`
- `scoring`
- `strict_exact_only`

`PrivSignal.Config.Loader` reads YAML through `YamlElixir`, validates it through `PrivSignal.Config.Schema`, and emits `[:priv_signal, :config, :load]` telemetry.

### PRD Nodes

PRD nodes are the authoritative catalog of privacy-relevant data attributes. Each node has:

- `key`
- `label`
- `class`
- `sensitive`
- `scope.module`
- `scope.field`

Allowed classes are centralized in `PrivSignal.Config.PRD` and include categories such as direct identifiers, persistent pseudonymous identifiers, behavioral signals, inferred attributes, and sensitive context indicators.

### Matching Options

`PrivSignal.Config.Matching` controls how source symbols are matched back to PRD nodes:

- `aliases`
- `split_case`
- `singularize`
- `strip_prefixes`

These settings are consumed by `PrivSignal.Scan.Inventory`.

### Scanner Options

`PrivSignal.Config.Scanners` holds scanner category settings for:

- logging
- HTTP
- controller
- telemetry
- database
- LiveView

Each scanner can be enabled or disabled. Some scanners accept additional module/function/domain hints.

### Scoring Options

`PrivSignal.Config.Scoring` still contains weights and thresholds for legacy score configuration, but current v2 scoring is categorical and uses `PrivSignal.Score.RubricV2`. The active scoring task also reads `scoring.llm_interpretation` for optional advisory commentary.

## Validation Internals

Validation has two layers.

`PrivSignal.Config.Schema` validates the YAML contract:

- `version` must be `1`.
- unsupported legacy keys such as `pii_modules`, `pii`, and `flows` are rejected.
- `prd_nodes` must be present, unique by key, and structurally valid.
- scanner and matching options must have expected shapes.
- scoring config must be well-formed if present.

`PrivSignal.Validate` validates configured PRD scopes against indexed source:

- `PrivSignal.Validate.AST` parses Elixir files and extracts module/function metadata.
- `PrivSignal.Validate.Index` builds a project-wide source index.
- `PrivSignal.Validate.Result` and `PrivSignal.Validate.Error` carry validation results.
- `PrivSignal.Validate.Output` formats CLI output.

The goal is to fail early when the catalog no longer matches the codebase.

## Scan Pipeline

The scan pipeline starts in `PrivSignal.Scan.Runner`.

At a high level:

```text
Config
  -> Inventory.build/1
  -> Source.files/1
  -> AST.parse_file/1 per source file
  -> category scanner modules
  -> raw candidates
  -> Classifier.classify/1
  -> scan result
```

### Inventory

`PrivSignal.Scan.Inventory` converts configured PRD nodes into searchable indexes:

- `data_nodes`
- `nodes_by_key`
- `nodes_by_module`
- exact token matches
- normalized token matches
- alias token matches

The inventory is what lets scanner modules connect code tokens such as `email`, `user_email`, or configured aliases back to PRD nodes.

### Source Discovery

`PrivSignal.Scan.Source` discovers Elixir files to scan. The runner then parses each file with `PrivSignal.Validate.AST.parse_file/1`.

### Concurrency and Timeouts

`PrivSignal.Scan.Runner` uses `Task.Supervisor.async_stream_nolink/5` to scan files concurrently. It caps concurrency at eight workers and supports:

- CLI option `--timeout-ms`
- CLI option `--max-concurrency`
- environment variable `PRIV_SIGNAL_SCAN_TIMEOUT_MS`
- environment variable `PRIV_SIGNAL_SCAN_MAX_CONCURRENCY`

Worker parse errors, timeouts, and exits are collected into the scan result instead of crashing the whole run unless strict mode requires failure.

### Scanner Modules

Scanner modules live under `PrivSignal.Scan.Scanner.*`. Each category implements `scan_ast/4` and returns raw candidates.

- `Logging`: detects PRD data in `Logger`, Erlang logger, metadata, wrapper calls, and bulk inspect patterns.
- `HTTP`: detects PRD data passed to outbound HTTP calls.
- `Controller`: detects PRD data exposed through controller response paths.
- `Telemetry`: detects PRD data emitted through telemetry and analytics calls.
- `Database`: detects PRD data in database reads/writes, including configured wrappers.
- `LiveView`: detects PRD data exposed through assigns, render paths, and events.

`PrivSignal.Scan.Scanner.Utils` provides AST helper functions. `PrivSignal.Scan.Scanner.Evidence` extracts PRD-node evidence from AST expressions. `PrivSignal.Scan.Scanner.Cache` precomputes per-file metadata shared across scanner categories.

### Classification

`PrivSignal.Scan.Classifier` converts raw candidates into `PrivSignal.Scan.Finding` structs.

The classifier decides:

- `classification`: `confirmed_prd` or `possible_prd`
- `confidence`: `confirmed`, `probable`, or `possible`
- `sensitivity`: highest sensitivity among matched nodes
- `data_classes`: involved PRD classes
- stable finding ID

Confirmed evidence includes direct field access, key matches, and PRD container evidence. Probable evidence includes indirect payload references and inherited database wrapper evidence.

See `docs/classification_registry.md` for the public `PS-SCAN-*` category registry.

## Inference and Lockfile Generation

The scan command writes the lockfile through the inference layer rather than directly through `PrivSignal.Scan.Output.*`.

`PrivSignal.Infer.Runner` wraps `PrivSignal.Scan.Runner` and converts scan findings into the lockfile model:

```text
scan findings
  -> ScannerAdapter.Logging.from_findings/2
  -> inferred nodes
  -> FlowBuilder.build/2
  -> inferred flows
  -> Infer.Output.JSON.render/1
  -> priv_signal.lockfile.json
```

### Nodes

`PrivSignal.Infer.Node` represents a normalized source, sink, boundary, or entrypoint node. Nodes include:

- stable `id`
- `node_type`
- `data_refs`
- `code_context`
- `role`
- `entrypoint_context`
- `confidence`
- `evidence`

`PrivSignal.Infer.NodeNormalizer` canonicalizes paths, roles, code context, data references, and evidence so lockfile output is stable across runs. `PrivSignal.Infer.NodeIdentity` generates deterministic IDs from normalized node attributes.

### Flows

`PrivSignal.Infer.FlowBuilder` groups nodes by module, function, and file path, then links data references to sinks in the same function context. It emits `PrivSignal.Infer.Flow` structs with:

- `id`, `stable_id`, and `variant_id`
- source information
- linked references and classes
- entrypoint
- sink kind/subtype
- boundary
- confidence
- evidence node IDs

`PrivSignal.Infer.FlowIdentity` generates stable and variant flow IDs. `PrivSignal.Infer.FlowScorer` estimates flow confidence from evidence signals such as direct references and same-function context.

External boundary classification is currently based on sink kinds such as HTTP, webhooks, S3, email, third-party destinations, telemetry, and LiveView rendering.

### Lockfile Contract

`PrivSignal.Infer.Contract` defines schema version `"1"` and validates generated artifacts. `PrivSignal.Infer.Output.JSON` writes maps with:

- `schema_version`
- `tool`
- `git`
- `summary`
- `data_nodes`
- `nodes`
- `flows`
- `errors`

The lockfile is generated, deterministic, and should not be hand-edited.

## Semantic Diff Pipeline

The diff pipeline starts in `PrivSignal.Diff.Runner`.

```text
options
  -> ArtifactLoader.load/2
  -> Normalize.normalize/1
  -> Semantic.compare_normalized/3
  -> Severity.annotate/1
  -> SemanticV2.from_changes/1
  -> ContractV2.validate_events/2
  -> Render.Human / Render.JSON
```

### Artifact Loading

`PrivSignal.Diff.ArtifactLoader` loads:

- the base artifact from a git ref
- the candidate artifact from the workspace by default
- or the candidate artifact from `--candidate-ref`

It validates loaded artifacts with `PrivSignal.Diff.Contract` and records metadata such as base ref, candidate source, and schema versions.

### Normalization

`PrivSignal.Diff.Normalize` converts lockfile artifacts into maps optimized for semantic comparison:

- data nodes indexed by key
- flow IDs and stable IDs
- flows indexed by ID
- normalized sink, source, boundary, confidence, linked refs, and location data

This isolates semantic comparison from JSON key ordering, formatting, and other artifact noise.

### Semantic Change Detection

`PrivSignal.Diff.Semantic` detects changes such as:

- added or removed flows
- sink changes
- boundary changes
- optional confidence changes
- new inferred attributes
- behavioral signal persistence
- inferred attribute external transfer
- sensitive context linkage added or removed

It also pairs flows by stable identity so variant-ID changes can still be compared as modifications when their stable semantics match.

### Severity Annotation

`PrivSignal.Diff.Severity` assigns deterministic severity and rule IDs to semantic changes. These map to public `PS-DIFF-*` categories in `docs/classification_registry.md`.

### V2 Event Conversion

`PrivSignal.Diff.SemanticV2` converts annotated legacy changes into the v2 event model consumed by scoring.

Events include:

- `event_id`
- `event_type`
- `event_class`
- `rule_id`
- `node_id`
- `edge_id`
- `location`
- `entrypoint_kind`
- boundary and sensitivity before/after
- destination
- `pii_delta`
- `transform_delta`
- raw `details`

`PrivSignal.Diff.EventId` generates stable event IDs. `PrivSignal.Diff.ContractV2` validates events before they are rendered or scored.

### Diff Outputs

`PrivSignal.Diff.Render.Human` renders reviewer-friendly CLI output. `PrivSignal.Diff.Render.JSON` emits v2 JSON:

- `version: "v2"`
- `metadata`
- `summary`
- `events`

The JSON artifact is the input contract for `mix priv_signal.score`.

## Scoring Pipeline

The scoring pipeline starts in `PrivSignal.Score.Engine`.

```text
tmp/privacy_diff.json
  -> Score.Input.load_diff_json/1
  -> Score.Engine.run/2
  -> RubricV2.classify_events/2
  -> score decision
  -> Score.Output.JSON.render/2
```

### Input Contract

`PrivSignal.Score.Input` accepts only semantic diff JSON version `"v2"` with an `events` array. Legacy diff versions are rejected.

### Rubric

`PrivSignal.Score.RubricV2` classifies known event types:

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

The rubric assigns an event class and rule ID. Examples:

- new external edge -> high, `R2-HIGH-NEW-EXTERNAL-PII-EGRESS`
- new internal edge -> medium, `R2-MEDIUM-NEW-INTERNAL-SINK`
- internal-to-external high-sensitivity boundary change -> high
- transform removal on an external path -> high
- residual privacy-relevant updates -> low

Unknown event types fail in strict mode and become low-severity warnings in non-strict mode.

### Final Score Decision

`PrivSignal.Score.Engine` chooses the PR-level score from classified events:

- `NONE` when `events_total == 0`
- `HIGH` when any high-class event exists
- `MEDIUM` when no high but at least one medium-class event exists
- `LOW` otherwise

The score reason list includes only events at the selected final score level. This keeps the output focused on the events that determined the PR-level result.

### Score Output

`PrivSignal.Score.Output.JSON` emits:

- `version: "v2"`
- `score`
- `summary`
- `reasons`
- `llm_interpretation`

`PrivSignal.Score.Output.Writer` writes the JSON artifact. The CLI also prints a concise `score=<VALUE>` summary unless `--quiet` is used.

## Optional Advisory LLM Path

The deterministic score path does not depend on an LLM.

`PrivSignal.Score.Advisory` can optionally produce commentary when `scoring.llm_interpretation.enabled` is set. The advisory path uses:

- `PrivSignal.LLM.Prompt`
- `PrivSignal.LLM.Client`
- `PrivSignal.LLM.Schema`
- legacy normalization and validation helpers under `PrivSignal.Analysis.*`

Advisory failures are non-fatal. The deterministic score artifact remains authoritative.

## Telemetry

Telemetry emission is centralized through `PrivSignal.Telemetry.emit/3`.

Important event families include:

- `[:priv_signal, :config, :load]`
- `[:priv_signal, :scan, :inventory, :build]`
- `[:priv_signal, :scan, :category, :run]`
- `[:priv_signal, :scan, :run]`
- `[:priv_signal, :infer, :run, :start]`
- `[:priv_signal, :infer, :flow, :build]`
- `[:priv_signal, :infer, :run, :stop]`
- `[:priv_signal, :diff, :artifact, :load]`
- `[:priv_signal, :diff, :normalize]`
- `[:priv_signal, :diff, :semantic, :compare]`
- `[:priv_signal, :diff, :render]`
- `[:priv_signal, :diff, :run, :start | :stop | :error]`
- `[:priv_signal, :score, :run, :start | :stop | :error]`
- `[:priv_signal, :score, :rule_hit]`

These events carry durations, counts, success flags, schema versions, strict-mode flags, and rule-hit metadata where relevant.

## Determinism

Determinism is enforced through repeated normalization and stable sorting:

- source files are discovered and processed into sorted result structures
- inventory data nodes are sorted by key/module/field/class/sensitivity
- scan findings use stable fingerprints and sort keys
- inferred nodes and flows are normalized before ID generation
- flow and node IDs are derived from semantic attributes
- diff artifacts are normalized before comparison
- semantic changes and v2 events are sorted by stable keys
- JSON renderers avoid relying on incidental traversal order for public arrays

This is what makes lockfiles reviewable and suitable for PR-to-base comparison.

## Extension Points

### Adding a Scanner Category

To add a new scan category:

1. Add or extend config support in `PrivSignal.Config.Scanners` and `PrivSignal.Config.Schema`.
2. Implement a scanner module with `scan_ast/4`.
3. Add it to `PrivSignal.Scan.Runner.scanner_modules_from_config/1`.
4. Return candidates with matched nodes, evidence, sink metadata, role hints, and boundary hints.
5. Extend tests and, if user-visible, update `docs/classification_registry.md`.

### Adding Evidence Types

Evidence collection is centralized in `PrivSignal.Scan.Scanner.Evidence`. If a new evidence type changes confidence semantics, update `PrivSignal.Scan.Classifier`.

### Changing Lockfile Shape

Lockfile changes should go through:

- `PrivSignal.Infer.Contract`
- `PrivSignal.Infer.Output.JSON`
- `PrivSignal.Diff.Contract`
- `PrivSignal.Diff.Normalize`
- tests for deterministic output and backward compatibility

### Adding Diff Semantics

New semantic changes generally require updates to:

- `PrivSignal.Diff.Semantic`
- `PrivSignal.Diff.Severity`
- `PrivSignal.Diff.SemanticV2`
- `PrivSignal.Diff.ContractV2`
- `docs/classification_registry.md`

### Adding Score Rules

New scoring behavior should update:

- `PrivSignal.Score.RubricV2`
- `PrivSignal.Score.Engine` only if final score decision logic changes
- `SCORING.md`
- `docs/classification_registry.md`
- score contract and decision-order tests

## Current Compatibility Notes

The repository contains legacy modules for earlier LLM-first and raw diff analysis paths. They remain in `lib/priv_signal/git`, `lib/priv_signal/risk`, `lib/priv_signal/analysis`, `lib/priv_signal/llm`, and `lib/priv_signal/output`.

The current primary path is deterministic:

```text
scan -> lockfile -> diff v2 events -> score v2
```

When maintaining the codebase, prefer extending the deterministic artifact-based path unless a change explicitly targets advisory or legacy behavior.
