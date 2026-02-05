# PRD: Deterministic Data Flow Validation (AST-Level)

## Summary
Add a new major feature to PrivSignal that validates data flow definitions in `priv-signal.yml` against the codebase. The feature reads each configured data flow and verifies that every referenced module and function still exists. This validation must be deterministic, correct, and fast. It must be invokable via a dedicated mix task and must run automatically as the first step of the existing `mix priv_signal.score` task.

## Problem Statement
PrivSignal currently relies on declarative data flow definitions that can drift from the actual codebase. Over time, renamed modules or refactored functions can make configured flows incorrect while still appearing valid in CI/CD scoring. This creates false confidence and reduces the reliability of PIA reassessment triggers.

## Goals
- Validate that each configured data flow in `priv-signal.yml` matches the codebase.
- Confirm that every referenced module and function exists.
- Provide deterministic, correct, and fast validation suitable for CI runs and large repositories.
- Support a collection of 12–20 data flows per run.
- Provide a direct mix task for validation and run it automatically at the start of `mix priv_signal.score`.

## Non-Goals
- No requirement on the specific implementation technique (e.g., AST parsing, compilation metadata). The PRD explicitly forbids manual source code parsing and LLM-based analysis.
- No requirement to infer or validate runtime behavior, dynamic dispatch, or metaprogramming beyond what is deterministically verifiable.
- No requirement to validate data transformations or parameter-level semantics.

## Users and Use Cases
- Security and privacy engineers validating that declared PIA-related data flows are real and current.
- CI/CD pipelines gating merges if declared data flows are stale or incorrect.

## Functional Requirements
1. **YAML Flow Ingestion**
   - Read all configured data flows from `priv-signal.yml`.
   - Each data flow is a sequence of module/function references.

2. **Symbol Existence Validation**
   - For each function in each flow, verify that the referenced module and function exists in the codebase.
   - Validation must report missing modules and missing functions distinctly.

3. **Batch Validation**
   - Must process 12–20 flows in a single run without manual intervention.
   - Results must be aggregated and summarized per flow with pass/fail status.

5. **Mix Task Invocation**
   - Provide a dedicated mix task to run validation (name to be defined by implementation).
   - `mix priv_signal.score` must invoke validation as the first step.
   - If validation fails, `mix priv_signal.score` must fail fast with a non-zero exit code.

6. **Determinism and Correctness**
   - Validation must be deterministic and correct under repeated runs on identical inputs.
   - Manual source parsing and LLM-based analysis are disallowed.

## Non-Functional Requirements
- **Performance**: Must complete quickly enough for CI usage (target under 30 seconds on a typical repo run; exact measurement to be confirmed during implementation).
- **Reliability**: Must produce consistent results across environments (local and CI).
- **Scalability**: Must handle 12–20 flows with potentially multi-module paths.
- **Determinism**: No stochastic or heuristic approaches.
- **Testability**: Must be easily to test this implmentation via unit tests within PrivSignal repository (likely by reading some data flows that traverse PrivSignal's OWN source code)

## UX and Output
- **CLI Output** should include:
  - Overall validation status (pass/fail).
  - Per-flow status with clear error messages.
  - If a flow fails, list missing modules/functions.
- **Exit Codes**:
  - `0` on full success.
  - Non-zero on any validation failure.

## Data and Configuration
- **Source of Truth**: The project that is using PrivSignal defines its own `priv-signal.yml`.
- **Flow Format**: Existing flow format used by PrivSignal; no format changes required by this PRD.

## Error Handling
- Fail with explicit errors for:
  - Missing or malformed `priv-signal.yml`.
  - Referenced modules or functions not found.
- Errors must be actionable and reference the flow name and the offending element.

## Observability
- Emit a structured summary of validation results to the console.
- No new telemetry requirements are mandated by this PRD.

## Security and Compliance
- Do not log secrets or sensitive configuration values from `priv-signal.yml`.

## Rollout and Compatibility
- Must be backward compatible with existing configurations.
- Validation is required for `mix priv_signal.score` and should be enabled by default once implemented.

## Success Metrics
- Reduced number of false positives from stale flow definitions.
- CI failures correctly indicating broken or outdated flow definitions.

## Open Questions
1. Exact mix task name for direct invocation.
2. How to handle dynamic dispatch, macros, or `apply/3` in a deterministic way (if required).
3. Definition of an acceptable performance threshold for very large repos.

## Acceptance Criteria
- Running the validation mix task on a repository with valid flows succeeds with exit code `0`.
- Running the validation mix task on a repository with a broken flow fails with a non-zero exit code and a clear message identifying the failed edge or missing symbol.
- `mix priv_signal.score` invokes validation first and fails fast on validation errors.
- Validation works reliably for 12–20 flows in a single run.
