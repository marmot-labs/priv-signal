PrivSignal – Functional/Technical Design (FDD)

1. Scope and Principles

This design implements the PRD as a small, composable Elixir CLI/Mix tool. Simpler is better: a clean module boundary for config, diff ingestion, LLM analysis, deterministic interpretation, and output formatting. PrivSignal is advisory only (exit code always 0), open source, and framework-agnostic.

2. High-Level Architecture

Pipeline (one-way):

1) Load config (priv-signal.yml)
2) Compute git diff (base/head)
3) Build LLM input (diff + config summary)
4) Call OpenAI API compatible LLM
5) Validate/normalize LLM JSON
6) Deterministic interpretation into risk events
7) Risk category assignment
8) Render outputs (Markdown + JSON)

3. Requirements Mapping (from PRD)

- Analyze only changed files/hunks from git diff.
- Use priv-signal.yml as authoritative system knowledge for flows and PII modules.
- LLM identifies: touched defined flows, new PII usage, new sinks/exports, privacy-relevant changes.
- LLM outputs structured JSON (not prose); must cite concrete evidence (file + line range) and uncertainty.
- Deterministic interpretation layer validates schema, evidence, and weights confidence.
- Risk categories: None/Low/Medium/High as defined in PRD.
- Outputs: Markdown summary + JSON artifact. Exit code always 0.
- CLI/Mix tasks: mix priv_signal.init, mix priv_signal.score, mix priv_signal.score --base ... --head ...
- OpenAI API compatible models supported; env vars override model URL and supply API keys.
- Integrates in local dev and CI (e.g., GitHub Actions). Advisory only (no enforcement).

4. Core Modules and Responsibilities

4.1 Configuration

- PrivSignal.Config.Loader
  - Reads priv-signal.yml from repo root.
  - Parses YAML into Elixir structs.
  - Validates required fields and semantics (modules/functions, flows, exits_system, third_party).
  - Output: %PrivSignal.Config{pii_modules, flows, version}.

- PrivSignal.Config.Schema
  - Declarative validation rules for priv-signal.yml (types, required fields, enums).
  - Keeps schema rules isolated so config validation stays simple.

- PrivSignal.Config.Summary
  - Builds a minimal structured summary of flows and PII modules for LLM prompt.

Data Structures
- PrivSignal.Config.Flow
  - id, description, purpose, pii_categories, path[], exits_system, third_party.
- PrivSignal.Config.PathStep
  - module, function.

4.2 Git Diff Input

- PrivSignal.Git.Diff
  - Invokes git to compute unified diff for base/head.
  - Supports defaults: base=origin/main, head=HEAD.
  - Output: raw unified diff string.

- PrivSignal.Git.Options
  - Parses CLI args for base/head overrides.

4.3 LLM Interaction

- PrivSignal.LLM.Client
  - HTTP client for OpenAI API compatible models.
  - Reads env:
    - PRIV_SIGNAL_MODEL_URL (override base URL)
    - PRIV_SIGNAL_MODEL_API_KEY (API key)
    - PRIV_SIGNAL_MODEL (optional model name; default TBD)
    - PRIV_SIGNAL_TIMEOUT_MS (connect timeout in ms)
    - PRIV_SIGNAL_RECV_TIMEOUT_MS (receive timeout in ms)
    - PRIV_SIGNAL_POOL_TIMEOUT_MS (pool checkout timeout in ms)
  - Sends messages and receives JSON response.

- PrivSignal.LLM.Prompt
  - Builds system/user prompts:
    - Instructions: reason only about added/modified lines; cite evidence; report uncertainty; output JSON only.
    - Inputs: unified diff + config summary.

- PrivSignal.LLM.Schema
  - Defines JSON schema for expected model output.
  - Example fields:
    - touched_flows: [{flow_id, evidence, confidence}]
    - new_pii: [{pii_category, evidence, confidence}]
    - new_sinks: [{sink, evidence, confidence}]
    - notes: [string]
  - Used by validation layer; schema can be simple but explicit.

4.4 Deterministic Interpretation

- PrivSignal.Analysis.Validator
  - Validates LLM output against schema.
  - Ensures evidence refers to file + line range and that lines exist in diff.

- PrivSignal.Analysis.Normalizer
  - Normalizes fields (canonical categories, de-duplicates evidence).
  - Applies confidence weighting and thresholds.

- PrivSignal.Analysis.Events
  - Converts normalized findings into internal risk events:
    - :flow_touched
    - :new_pii
    - :new_sink
    - :external_transfer
    - :sensitive_data

4.5 Risk Scoring

- PrivSignal.Risk.Rules
  - Encodes PRD logic for None/Low/Medium/High.
  - Pure, deterministic rules based on events and config.

- PrivSignal.Risk.Assessor
  - Computes final risk category.
  - Provides contributing factors for output.

4.6 Outputs

- PrivSignal.Output.Markdown
  - Generates PR comment markdown:
    - Risk category
    - Bullet list of contributing factors
    - Evidence excerpts (file + line ranges)

- PrivSignal.Output.JSON
  - Emits machine-readable JSON artifact:
    - risk_category
    - events
    - evidence
    - LLM confidence

- PrivSignal.Output.Writer
  - Writes outputs to stdout and optional files.
  - Ensures exit code always 0.

4.7 CLI / Mix Tasks

- PrivSignal.CLI
  - Entry for Mix tasks.
  - Subcommands:
    - mix priv_signal.init
    - mix priv_signal.score [--base ... --head ...]

- PrivSignal.CLI.Init
  - Scaffolds a starter priv-signal.yml in repo root.

- PrivSignal.CLI.Score
  - Orchestrates pipeline end-to-end.

5. Module Interaction Diagram (Narrative)

PrivSignal.CLI.Score
  -> PrivSignal.Config.Loader + PrivSignal.Config.Schema
  -> PrivSignal.Git.Diff (base/head)
  -> PrivSignal.LLM.Prompt (diff + config summary)
  -> PrivSignal.LLM.Client (OpenAI API compatible)
  -> PrivSignal.Analysis.Validator + PrivSignal.Analysis.Normalizer
  -> PrivSignal.Analysis.Events
  -> PrivSignal.Risk.Assessor (uses PrivSignal.Risk.Rules)
  -> PrivSignal.Output.Markdown + PrivSignal.Output.JSON
  -> PrivSignal.Output.Writer (stdout/files, exit 0)

6. Risk Categorization Rules (PRD Coverage)

- None: no defined flows touched; no new PII; no new sinks/exports.
- Low: touches existing YAML-defined flows; no new PII; no new data leaving system.
- Medium: new PII categories internally; new internal persistence/export; or existing flows expanded.
- High: new third-party transfer; new PII usage outside defined flows; sensitive data categories; new bulk exports/logging of PII.

Rules are implemented in PrivSignal.Risk.Rules with explicit checks against events derived from LLM output and config flags (exits_system, third_party).

7. Environment Configuration

Required for LLM usage:
- PRIV_SIGNAL_MODEL_API_KEY: API key for the model provider.
- PRIV_SIGNAL_SECONDARY_API_KEY: maps to the OpenAI org key for compatible endpoints.

Optional:
- PRIV_SIGNAL_MODEL_URL: overrides the default OpenAI-compatible base URL.
- PRIV_SIGNAL_MODEL: model identifier (kept simple; default can be hard-coded).
- PRIV_SIGNAL_TIMEOUT_MS: socket connect timeout in milliseconds.
- PRIV_SIGNAL_RECV_TIMEOUT_MS: socket receive timeout in milliseconds.
- PRIV_SIGNAL_POOL_TIMEOUT_MS: pool checkout timeout in milliseconds.

8. Error Handling and Safety

- Any failures should surface as warnings in output while still producing a JSON artifact and exit code 0.
- LLM errors or schema mismatches should degrade to “None” or lowest safe classification with a note indicating inability to analyze.
- Config validation errors reported in output; no hard failure.

9. Testing Plan (Lightweight)

- Unit tests for:
  - priv-signal.yml parsing + schema validation
  - risk rules mapping events -> category
  - LLM output validator
- Integration test:
  - Mock diff + mock LLM response -> expected Markdown/JSON.

10. Minimal Implementation Notes

- Keep dependencies minimal (YAML parser, HTTP client, JSON encoder).
- No static analysis or AST parsing in this phase.
- Prefer small pure functions for predictability.
