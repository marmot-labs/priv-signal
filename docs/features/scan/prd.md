# PRD: PII Inventory & Logging Scanner for PrivSignal

## Summary
Add a new feature to PrivSignal that builds a project-defined PII inventory and scans source code for boundary-sensitive PII exposure points, starting with logging statements. The initial release focuses on deterministic, AST-based static analysis guided by explicit YAML PII declarations, and reports actionable findings with evidence and confidence.

## Problem Statement
Elixir/Phoenix applications commonly log structured runtime data for debugging and observability. Without explicit safeguards, logs can include sensitive personal data (for example emails, phone numbers, and identifiers), which can then be retained, forwarded to third-party processors, and accessed more broadly than intended.

PrivSignal currently emphasizes PR-level flow change assessment, but it does not provide a baseline inventory answering: where might PII be exposed through logging or other sinks? This feature fills that gap by introducing a structured PII declaration and an AST-driven scanner that detects confirmed and potential PII usage at sensitive call sites.

## Goals
- Provide a clear inventory of PII fields defined in the system from explicit configuration.
- Identify logging statements that include PII fields or PII-bearing structures.
- Classify findings by confidence and sensitivity to support prioritization.
- Produce actionable output with file, function, and line-level evidence.
- Integrate cleanly with existing PrivSignal workflows and configuration.

## Non-Goals
- Full taint analysis or end-to-end runtime data-flow tracking.
- Automatic blocking of builds or PRs in the initial release.
- Broad sink coverage beyond logging in v1 (for example HTTP, exports, telemetry, persistence).
- Automatic runtime redaction or enforcement.

## Users and Use Cases
- Developers declaring PII fields so scanning stays accurate and project-specific.
- Developers and reviewers identifying and remediating accidental PII logging.
- Privacy engineers maintaining an auditable inventory of potential exposure points.

## Functional Requirements
1. **PII Declaration in YAML (Source of Truth)**
   - Introduce a structured `pii` section in `priv-signal.yml` replacing the previous `pii_modules`
   - Each entry must define a `module` and a `fields` list.
   - Each field must include `name`, with `category` and `sensitivity` metadata.
   - The declaration is authoritative for what counts as PII in the project.

2. **PII Inventory Generation**
   - Build an internal inventory from YAML declarations using deterministic processing.
   - Inventory must include:
     - PII container modules.
     - Declared PII fields and metadata.
     - Derived key names usable in map/keyword/params matching.

3. **Logging Scanner (Initial Scope)**
   - Scan source via AST for logging calls including:
     - `Logger.debug/1`, `Logger.info/1`, `Logger.error/1`, etc.
     - `Logger.log/2`.
     - Erlang logger calls (`:logger.*`).
     - Structured logging payloads (maps/keywords/metadata).
   - Mark findings as PII-relevant when evidence includes:
     - Direct PII field access (for example `user.email`).
     - PII fields used as map/keyword keys (for example `%{email: email}`, `[phone: phone]`).
     - Logging a declared PII container (for example `inspect(user)` where `user` is a PII module struct).
     - Suspicious bulk logging with matching PII keys (for example `inspect(params)`).
   

4. **Finding Classification**
   - Classify findings as:
     - `confirmed_pii` for direct field/container evidence.
     - `possible_pii` for dynamic or indirect evidence.

5. **Evidence and Context**
   - Each finding must include:
     - Module, function, and arity.
     - File path and line number.
     - Logging level/method.
     - Matched PII fields and associated metadata.
     - Sensitivity summary (for example high-sensitivity field involved).
     - Confidence label (`confirmed` or `possible`).

6. **Reporting Formats**
   - Provide JSON output for CI/tooling usage.
   - Provide Markdown output for human review.
   - Output should be an inventory of PII-relevant logging findings, not all logs.

## Non-Functional Requirements
- **Determinism**: Identical code/config inputs must produce identical findings.
- **Performance**: Suitable for local and CI usage on typical Elixir repositories.
- **Precision**: Prefer explicit, explainable matches based on declared PII over broad heuristics.
- **Maintainability**: Scanner rules should be extensible to future sink categories.
- **Extensibility**: This is the most important non-functional requirement as we intend to expand beyond scanner for just logging and eventually scan for controller, live_views, network HTTP calls, etc.  

## UX and Output
- Output should surface concise, explainable findings with clear severity/confidence.
- Example conceptual finding:

```
[HIGH] Confirmed PII in logs
Location: Oli.Accounts.Auth.login/2 (auth.ex:84)
Evidence: user.email (category: contact, sensitivity: medium)
Logger level: info
```

## Data and Configuration
- Add a new configuration section in `priv-signal.yml` (replacing the `pii_modules`)

```yaml
pii:
  - module: Oli.Accounts.User
    fields:
      - name: email
        category: contact
        sensitivity: medium
      - name: phone
        category: contact
        sensitivity: medium
      - name: dob
        category: special
        sensitivity: high
```

- Semantics:
  - `module` identifies a PII-bearing struct/schema.
  - `fields` lists only fields considered PII.
  - `category` and `sensitivity` are informational in v1 and reserved for richer policy/scoring in later phases.

## Error Handling
- Fail with explicit configuration errors when the `pii` section is malformed.
- Surface scanner parsing/indexing errors without leaking secrets.
- Distinguish config errors from scan findings.

## Observability
- Emit structured scan summaries suitable for CLI and CI logs.
- Include counts by confidence level and sensitivity tier.

## Security and Compliance
- Avoid logging sensitive field values during scanning/reporting.
- Restrict evidence to code references and symbol-level context.
- Treat PII declarations as potentially sensitive project metadata.

## Rollout and Compatibility
- Introduce as an additive feature that does not break existing flow-scoring workflows.
- Initial release focuses on logging sinks only; broader sink support is deferred.

## Success Metrics
- Scanner correctly identifies declared-PII usage in logging statements.
- Findings are actionable with low-noise output.
- Teams can use results to remediate accidental PII exposure paths.
- Feature adoption without disruption to existing PrivSignal usage.

## Open Questions
1. Exact CLI surface for invoking scanner-only vs combined workflows.
2. Whether confidence/sensitivity should map to existing risk categories in v1 or a separate report scale.
3. Minimum threshold for marking bulk logging as `possible_pii` to balance recall vs noise.
4. How to model aliases/wrappers around `Logger` and `:logger` in initial implementation.

## Acceptance Criteria
- A repository with valid `pii` declarations can produce a deterministic PII logging inventory.
- Logging calls that reference declared PII fields are reported as `confirmed_pii` with location and evidence.
- Indirect/dynamic logging cases matching declared PII keys are reported as `possible_pii`.
- JSON and Markdown outputs include module/function/file/line evidence and sensitivity/confidence context.
- Existing PrivSignal workflows continue to work when scanner configuration is absent or disabled.
