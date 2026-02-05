PrivSignal Development Plan

Scope
- Implement an Elixir CLI/Mix tool that scores PR diffs for privacy risk using priv-signal.yml + LLM + deterministic rules.
- Outputs: Markdown summary + JSON artifact. Exit code always 0.
- Support OpenAI API compatible models with env var overrides for model URL and API key.

Non-Functional Guardrails
- Deterministic interpretation and scoring; LLM never assigns risk label.
- Advisory only; no CI blocking; exit code always 0.
- Minimal dependencies; small, composable modules.
- Evidence-based output with file + line ranges.
- Works with local dev and CI (GitHub Actions invocation).

Clarifications (Defaults if Unanswered)
- Default model name: gpt-5.
- priv-signal.yml location: assume repo root only.
- Output locations: assume Markdown to stdout and JSON to a file (e.g., priv-signal.json) unless configured.
- Evidence validation: assume evidence line ranges must exist in diff hunks.
- YAML schema: assume version is required and must be 1.

Phase 0: Project Skeleton & Config Parsing
Goal
- Establish basic Mix task entry points and parse/validate priv-signal.yml.

Tasks
- [ ] Create Mix tasks: mix priv_signal.init and mix priv_signal.score.
- [ ] Implement PrivSignal.Config.Loader to read priv-signal.yml from repo root.
- [ ] Implement PrivSignal.Config.Schema validation with required fields and types.
- [ ] Implement PrivSignal.Config structs (Flow, PathStep, Config).
- [ ] Implement priv_signal.init scaffolding with minimal sample config.
- [ ] Add docs for config schema and example (in README or docs).

Tests
- [ ] Unit: priv-signal.yml parsing happy path.
- [ ] Unit: validation failures for missing fields or invalid types.
- [ ] Unit: priv_signal.init writes example config.
- [ ] Run: mix test --only config

Definition of Done
- Mix tasks exist and run without crashing.
- priv-signal.yml is parsed into structs; invalid config produces validation errors.
- Tests pass.

Gate Criteria
- All Phase 0 tests pass.
- priv_signal.init produces a valid priv-signal.yml.

Phase 1: Git Diff Ingestion
Goal
- Compute unified diff between base/head commits and surface to pipeline.

Tasks
- [ ] Implement PrivSignal.Git.Diff to run git diff --unified and return string.
- [ ] Implement PrivSignal.Git.Options for base/head flags.
- [ ] Wire base/head flags into mix priv_signal.score.
- [ ] Add error handling if git diff fails (report in output; still exit 0).

Tests
- [ ] Unit: base/head options parsing.
- [ ] Integration: mock git diff command output.
- [ ] Run: mix test --only git

Definition of Done
- priv_signal.score can read base/head and obtain diff string.
- Failures are surfaced in output but exit code is 0.
- Tests pass.

Gate Criteria
- All Phase 1 tests pass.

Phase 2: LLM Prompting + Client Stub
Goal
- Build prompt and call OpenAI-compatible endpoint (mocked in tests).

Tasks
- [ ] Implement PrivSignal.Config.Summary to summarize flows + PII modules for prompt.
- [ ] Implement PrivSignal.LLM.Prompt to construct system/user messages and JSON-only instruction.
- [ ] Implement PrivSignal.LLM.Client with env vars: PRIV_SIGNAL_MODEL_API_KEY, PRIV_SIGNAL_SECONDARY_API_KEY, PRIV_SIGNAL_MODEL_URL, PRIV_SIGNAL_MODEL, PRIV_SIGNAL_TIMEOUT_MS, PRIV_SIGNAL_RECV_TIMEOUT_MS, PRIV_SIGNAL_POOL_TIMEOUT_MS.
- [ ] Implement a basic JSON schema definition for expected LLM output.
- [ ] Add LLM error handling (timeout, invalid JSON) with safe fallback.

Tests
- [ ] Unit: prompt assembly includes diff + config summary.
- [ ] Unit: env var resolution and defaults.
- [ ] Unit: JSON schema validation for minimal response.
- [ ] Integration: mock HTTP response and ensure JSON is parsed.
- [ ] Run: mix test --only llm

Definition of Done
- Prompt and client can produce a valid JSON response from a mock server.
- Errors degrade gracefully and are reported.
- Tests pass.

Gate Criteria
- All Phase 2 tests pass.

Phase 3: Deterministic Interpretation Layer
Goal
- Validate, normalize, and convert LLM output into internal risk events.

Tasks
- [ ] Implement PrivSignal.Analysis.Validator to validate schema + evidence references in diff.
- [ ] Implement PrivSignal.Analysis.Normalizer for confidence thresholds and de-dup.
- [ ] Implement PrivSignal.Analysis.Events to create canonical event structs.

Tests
- [ ] Unit: evidence must reference file + line range in diff.
- [ ] Unit: normalization de-duplicates and canonicalizes categories.
- [ ] Run: mix test --only analysis

Definition of Done
- LLM output is deterministically validated and converted to events.
- Tests pass.

Gate Criteria
- All Phase 3 tests pass.

Phase 4: Risk Rules and Scoring
Goal
- Assign risk category per PRD based on events and config.

Tasks
- [ ] Implement PrivSignal.Risk.Rules for None/Low/Medium/High.
- [ ] Implement PrivSignal.Risk.Assessor to select category and contributing factors.

Tests
- [ ] Unit: coverage for each risk category path.
- [ ] Unit: edge cases (conflicting signals, no data).
- [ ] Run: mix test --only risk

Definition of Done
- Risk category is deterministic and aligned with PRD definitions.
- Tests pass.

Gate Criteria
- All Phase 4 tests pass.

Phase 5: Output Formatting and Orchestration
Goal
- End-to-end pipeline produces Markdown + JSON outputs and exits 0.

Tasks
- [ ] Implement PrivSignal.Output.Markdown generator.
- [ ] Implement PrivSignal.Output.JSON generator.
- [ ] Implement PrivSignal.Output.Writer for stdout/file outputs.
- [ ] Wire PrivSignal.CLI.Score pipeline from config -> diff -> LLM -> analysis -> risk -> output.
- [ ] Add CLI flags for output locations if needed.

Tests
- [ ] Integration: end-to-end flow with fixture diff and mocked LLM.
- [ ] Unit: markdown output format includes category, factors, evidence.
- [ ] Unit: JSON output schema.
- [ ] Run: mix test --only output

Definition of Done
- Running mix priv_signal.score emits Markdown and JSON without error.
- Exit code always 0.
- Tests pass.

Gate Criteria
- All Phase 5 tests pass.

Phase 6: CI/Docs/Observability
Goal
- Ensure usability in CI and maintainable docs.

Tasks
- [ ] Document GitHub Actions usage and environment variables.
- [ ] Add telemetry/logging hooks for key steps (config load, diff, LLM call, scoring).
- [ ] Add README quickstart with mix priv_signal.init and mix priv_signal.score examples.

Tests
- [ ] Unit: telemetry events emitted (using :telemetry test hooks).
- [ ] Run: mix test --only telemetry

Definition of Done
- Docs clearly explain setup, env vars, and outputs.
- Basic telemetry is present.
- Tests pass.

Gate Criteria
- All Phase 6 tests pass.

Dependency Order (Topological, Risk-First)
1) Phase 0 (config and tasks)
2) Phase 1 (git diff)
3) Phase 2 (LLM prompt/client)
4) Phase 3 (analysis layer)
5) Phase 4 (risk rules)
6) Phase 5 (outputs and orchestration)
7) Phase 6 (docs/telemetry)
