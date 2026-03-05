# Torus Staged PR Generation Prompt (PrivSignal Validation)

Use this document as the direct prompt/instruction set for a coding agent operating in the Torus repository.

## Objective

Create **10 separate Torus branches/PRs** that intentionally introduce realistic privacy-relevant code changes so PrivSignal can be validated against known drift.

Each branch should target specific registry items from:

- [`docs/classification_registry.md`](./classification_registry.md)

The goal is controlled signal generation for PrivSignal, not production-hardening.

## Workspace Context

- You (the coding agent) will execute in: `../oli-torus`
- PrivSignal source repo is a sibling directory: `../priv-signal`
- Integration base branch in Torus: `privsignal-integration`
- Read the classification registry in PrivSignal before making changes:
  - `../priv-signal/docs/classification_registry.md`

## Output Requirements

Create exactly 10 branches with this naming convention:

- `ps-torus-01-<slug>`
- `ps-torus-02-<slug>`
- `...`
- `ps-torus-10-<slug>`

Use concise, meaningful slugs (e.g., `none-control`, `internal-logging-medium`, `external-http-high`).

For each branch:

1. Make a realistic code change in Torus inspired by examples in the classification registry.
2. Keep changes intentionally minimal but material.
3. Do not include unrelated refactors.
4. Commit changes on that branch.
5. Provide a short branch summary mapping expected:
   - `PS-SCAN-*`
   - `PS-DIFF-*`
   - `PS-SCORE-*`

## Mandatory Constraints

- **Do not write unit tests or integration tests.**
- **Do not perform QA hardening.**
- This is prototype/instrumentation-style diff generation only.
- Code should be plausible and preferably compile, but test coverage is explicitly out of scope.

## Recommended Branch Matrix (Target Coverage)

Implement the following intent profile across the 10 branches. You may choose concrete Torus files/modules, but preserve the expected signal intent.

1. `ps-torus-01-none-control`
   - Intent: meaningful non-privacy code change (control)
   - Expected: no meaningful PrivSignal delta
   - Targets: score outcome `NONE`

2. `ps-torus-02-low-flow-removed`
   - Intent: remove existing privacy-relevant sink/log/export
   - Targets: `PS-DIFF-003`, low outcome path

3. `ps-torus-03-medium-internal-logging`
   - Intent: add internal logging of PRD field
   - Targets: `PS-SCAN-001/002`, `PS-DIFF-002`, `PS-SCORE-005`

4. `ps-torus-04-high-external-http-egress`
   - Intent: add outbound HTTP with PRD field
   - Targets: `PS-SCAN-005`, `PS-DIFF-001`, `PS-SCORE-001`

5. `ps-torus-05-high-controller-response-exposure`
   - Intent: expose PRD fields in controller JSON/response path
   - Targets: `PS-SCAN-006`, high score path

6. `ps-torus-06-high-liveview-client-exposure`
   - Intent: emit PRD data through LiveView `assign`/`push_event`
   - Targets: `PS-SCAN-009`, high score path

7. `ps-torus-07-high-telemetry-export`
   - Intent: include PRD data in telemetry analytics metadata
   - Targets: `PS-SCAN-007`, high score path

8. `ps-torus-08-medium-behavioral-persisted`
   - Intent: newly persist behavioral signal internally
   - Targets: `PS-DIFF-009`, `PS-SCORE-007` or medium path

9. `ps-torus-09-high-inferred-attribute-external-transfer`
   - Intent: send inferred attribute externally
   - Targets: `PS-DIFF-010`, `PS-SCORE-002` or equivalent high path

10. `ps-torus-10-high-transform-removed`
   - Intent: remove sensitive context linkage/transform on external flow
   - Targets: `PS-DIFF-012`, `PS-SCORE-004`

## Branch Execution Protocol

For each branch:

1. Start from Torus branch `privsignal-integration` (do **not** branch from `main`/`master`).
2. Create branch using naming convention above.
3. Apply only the intended change pattern for that branch.
4. Commit with message prefix:
   - `privsignal-stage-XX: <intent>`
5. Record expected PrivSignal mapping in commit body or branch notes:
   - `Expected PS-SCAN: ...`
   - `Expected PS-DIFF: ...`
   - `Expected PS-SCORE: ...`

## Deliverable Format

After all 10 branches are created, return a table:

- Branch name
- Files changed
- One-line change description
- Expected `PS-SCAN-*`
- Expected `PS-DIFF-*`
- Expected `PS-SCORE-*`

## Non-Goals

- No production-ready hardening
- No QA/test authoring
- No documentation churn outside what is needed to explain branch intent
- No broad refactors

This task is exclusively for generating controlled, realistic privacy drift diffs to validate PrivSignal behavior.
