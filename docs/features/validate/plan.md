PrivSignal Validate Feature Plan (Symbol-Only)

Scope
- Implement deterministic symbol validation against Elixir source code.
- Build an AST-derived index of modules and functions.
- Run validation before `mix priv_signal.score`.
- Provide clear missing module/function errors and non-zero exits.

Core Validation Rules
1. `step.module` must exist.
2. `step.function` must exist in that module (any arity).

Out of Scope
- Call-edge detection.
- Ambiguous call tracking.
- Runtime path inference.

Implementation Tasks
- [x] AST parsing for modules/functions.
- [x] Symbol index build (`modules`, `functions`).
- [x] Flow validation for missing module/function only.
- [x] `mix priv_signal.validate` output + exit semantics.
- [x] `mix priv_signal.score` fail-fast integration.
- [x] Tests and fixtures aligned to symbol-only behavior.

Acceptance Criteria
- Valid symbols => `mix priv_signal.validate` exits `0`.
- Missing module/function => non-zero exit with clear error.
- `mix priv_signal.score` fails fast only on symbol validation failures.

