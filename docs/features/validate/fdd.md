# FDD: Deterministic Symbol Validation

## Summary
Validation checks that every `module` and `function` listed in each flow path in
`priv-signal.yml` still exists in source code. Validation is deterministic, AST-based,
and runs before scoring.

## Goals
- Validate configured flows against code symbols.
- Report missing modules distinctly from missing functions.
- Fail fast in `mix priv_signal.validate` and `mix priv_signal.score`.
- Keep runtime deterministic and CI-friendly.

## Approach
Use Elixir AST parsing (`Code.string_to_quoted`) to build an index:
- `modules`: `MapSet` of module names.
- `functions`: module => `MapSet` of `{function_name, arity}`.

Validation rules:
1. Every `step.module` must exist in `index.modules`.
2. Every `step.function` must exist in `index.functions[step.module]` (any arity match).

No call-edge continuity is enforced.

## Architecture
- `PrivSignal.Validate.AST`: parse files, extract modules/functions.
- `PrivSignal.Validate.Index`: build symbol index.
- `PrivSignal.Validate`: validate flows against symbol index.
- `mix priv_signal.validate`: CLI task.
- `mix priv_signal.score`: invokes validation first and fails fast on symbol errors.

## Error Types
- `:missing_module`
- `:missing_function`

## CLI Behavior
- `data flow validation: ok` when all symbols are present.
- `data flow validation: error` when any symbol is missing.
- Non-zero exit on error.

## Telemetry
- `[:priv_signal, :validate, :index]`:
  - `duration_ms`, `file_count`, `module_count`, `function_count`, `ok`, `error_count?`
- `[:priv_signal, :validate, :run]`:
  - `duration_ms`, `flow_count`, `status`, `error_count`, `ok`

## Limitations
- Does not validate runtime call paths or dynamic dispatch.
- Does not infer behavioral dataflow; validates symbol existence only.

