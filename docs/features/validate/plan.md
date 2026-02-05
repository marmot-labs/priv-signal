PrivSignal Validate Feature Plan

Scope
- Implement deterministic data-flow validation against Elixir source code.
- Build an AST-derived index of modules, functions, and call edges.
- Add a dedicated mix task and run validation before mix priv_signal.score.
- Provide clear errors and non-zero exit on validation failures.

Non-Functional Guardrails
- Deterministic behavior across runs and environments.
- No manual source parsing; no LLM usage.
- Fast enough for CI (target <30s on typical repos).
- Minimal dependencies; leverage standard Elixir tooling.

Clarifications (Defaults if Unanswered)
- Mix task name: mix priv_signal.validate.
- Validate only .ex files under Mix.Project.config()[:elixirc_paths].
- Flow step function names match any arity.
- Dynamic dispatch (apply/3, computed module/function) is not validated.

Phase 0: AST Parsing Primitives
Goal
- Establish reliable AST parsing and extraction helpers.

Tasks
- [x] Implement PrivSignal.Validate.AST.parse_file/1 using Code.string_to_quoted with metadata.
- [x] Implement module extraction from defmodule nodes with fully-qualified name strings.
- [x] Implement function extraction (def/defp) with name + arity.
- [x] Implement call extraction for remote calls and local calls.

Tests
- [x] Unit: parse_file returns {:ok, ast} for valid source and {:error, reason} for invalid source.
- [x] Unit: module extraction returns correct module name for nested aliases.
- [x] Unit: function extraction captures name + arity for def/defp with guards.
- [x] Unit: call extraction captures Mod.fun/arity and local calls.

Definition of Done
- AST helpers return deterministic, structured outputs for modules, functions, and calls.
- Phase 0 tests pass.

Gate Criteria
- All Phase 0 tests pass.

Phase 1: Alias/Import Resolution + Source Index
Goal
- Resolve aliases/imports and build a project-wide index of modules, functions, and call edges.

Tasks
- [ ] Implement alias tracking (alias Mod, alias Mod, as: Alias) with alias map.
- [ ] Implement import tracking with only/except filtering.
- [ ] Implement module resolution for __MODULE__ and aliased module references.
- [ ] Implement PrivSignal.Validate.Index.build/0 to enumerate elixirc_paths and parse .ex files.

Tests
- [ ] Unit: alias resolution replaces local alias with full module name.
- [ ] Unit: import resolution respects only/except for a local call.
- [ ] Unit: index builder records modules and functions across multiple files.
- [ ] Unit: index builder records call edges for local and remote calls.

Definition of Done
- Index build produces stable modules/functions/calls maps for the project.
- Phase 1 tests pass.

Gate Criteria
- All Phase 1 tests pass.

Phase 2: Validation Engine
Goal
- Validate configured flows against the index with precise error reporting.

Tasks
- [ ] Define PrivSignal.Validate.Result and PrivSignal.Validate.Error structs.
- [ ] Implement flow validation for module existence.
- [ ] Implement flow validation for function existence (name matches any arity).
- [ ] Implement call-chain validation across adjacent path steps.
- [ ] Implement ambiguous import handling and error reporting.

Tests
- [ ] Unit: missing module produces :missing_module error.
- [ ] Unit: missing function produces :missing_function error.
- [ ] Unit: missing edge produces :missing_edge error.
- [ ] Unit: ambiguous import produces :ambiguous_call error.

Definition of Done
- Flow validation returns deterministic results with specific error types.
- Phase 2 tests pass.

Gate Criteria
- All Phase 2 tests pass.

Phase 3: Mix Task + CLI Output
Goal
- Provide a user-facing validation command with clear output and exit codes.

Tasks
- [ ] Implement Mix.Tasks.PrivSignal.Validate to load config, build index, validate flows.
- [ ] Implement CLI output formatting for overall and per-flow status.
- [ ] Implement non-zero exit on any validation failure.

Tests
- [ ] Integration: mix priv_signal.validate returns 0 on success.
- [ ] Integration: mix priv_signal.validate returns non-zero on failure.
- [ ] Unit: output formatter includes flow id and failing edge/module/function.

Definition of Done
- Validation can be invoked directly and reports actionable errors.
- Phase 3 tests pass.

Gate Criteria
- All Phase 3 tests pass.

Phase 4: Score Task Integration
Goal
- Ensure validation runs first in mix priv_signal.score and fails fast on errors.

Tasks
- [ ] Wire validation into Mix.Tasks.PrivSignal.Score after config load.
- [ ] Ensure score task halts before diff/LLM steps on validation failure.

Tests
- [ ] Integration: mix priv_signal.score fails fast when validation fails.
- [ ] Integration: mix priv_signal.score continues when validation succeeds.

Definition of Done
- Score task invokes validation as the first step and respects failures.
- Phase 4 tests pass.

Gate Criteria
- All Phase 4 tests pass.

Phase 5: End-to-End Fixtures and Documentation
Goal
- Validate behavior on realistic fixtures and document usage.

Tasks
- [ ] Add test fixtures under test/fixtures/validate for passing and failing flows.
- [ ] Add README or docs/validate note documenting mix priv_signal.validate usage.

Tests
- [ ] Integration: fixture flow passes with correct call chain.
- [ ] Integration: fixture flow fails with missing edge and reports it.

Definition of Done
- Fixture-based tests cover pass/fail cases.
- Documentation describes how to run validation.
- Phase 5 tests pass.

Gate Criteria
- All Phase 5 tests pass.

Dependency Order (Topological, Risk-First)
1) Phase 0 (AST primitives)
2) Phase 1 (resolution + index)
3) Phase 2 (validation engine)
4) Phase 3 (mix task + CLI)
5) Phase 4 (score integration)
6) Phase 5 (fixtures + docs)
