# FDD: Deterministic Data Flow Validation

## Summary
This design adds deterministic validation of flow definitions in `priv-signal.yml` by building a static call graph from the project’s Elixir source and verifying that each configured call chain is present. The approach is purely deterministic, uses the Elixir parser and AST, avoids manual parsing and LLMs, and is fast enough for CI.

## Goals (from PRD)
- Validate that each configured data flow matches code.
- Verify modules and functions exist.
- Verify each call edge exists (`A -> B -> C -> D`).
- Deterministic, correct, fast.
- Runs for 12–20 flows.
- Invokable via mix task and executed first in `mix priv_signal.score`.

## Recommended Approach
### Source-Level AST Index + Call Graph
Use Elixir’s built-in parser (`Code.string_to_quoted`) to parse project source files into AST. Build a static index of:
- Modules defined in the project
- Functions defined per module (name + arity)
- Call edges per function (caller -> callee)

Then validate each configured flow path against this index:
- Module exists
- Function exists (any arity matching name)
- Each adjacent pair is present as a call edge

This approach is deterministic, does not rely on runtime execution, and does not manually parse source. It avoids inlining issues that can appear in BEAM-based call graphs.

## Architecture
**New modules** (names are suggestions; final names can align with existing structure):
- `PrivSignal.Validate` — orchestration, public API.
- `PrivSignal.Validate.Index` — builds module/function index and call graph.
- `PrivSignal.Validate.AST` — AST helpers for module/function/call extraction.
- `PrivSignal.Validate.Result` — result structs and formatting helpers.

**Mix tasks**:
- `mix priv_signal.validate` — direct invocation.
- `mix priv_signal.score` — calls validation first and fails fast on errors.

## Data Model
### Internal Index
```elixir
%{
  modules: MapSet.t(String.t()),
  functions: %{module_string => MapSet.t({function_name, arity})},
  calls: %{
    {caller_module_string, caller_fun_name, caller_arity} =>
      MapSet.t({callee_module_string, callee_fun_name, callee_arity})
  }
}
```

### Validation Result
```elixir
%PrivSignal.Validate.Result{
  flow_id: String.t(),
  status: :ok | :error,
  errors: [PrivSignal.Validate.Error.t()]
}
```

Errors capture:
- `:missing_module` (flow_id, module)
- `:missing_function` (flow_id, module, function)
- `:missing_edge` (flow_id, from_module, from_function, to_module, to_function)
- `:ambiguous_call` (flow_id, caller, fun, candidates)

## Detailed Design

### 1) Load Config
Reuse `PrivSignal.Config.Loader.load/1`. We already get a `%PrivSignal.Config{flows: [...]}` with `%PathStep{module, function}` where both are strings.

### 2) Build Source Index
**Inputs**
- Source files under `Mix.Project.config()[:elixirc_paths]` (default `lib`), plus `.ex` files under those directories.

**Process**
1. Enumerate files using `Path.wildcard(Path.join(path, "**/*.ex"))`.
2. For each file:
   - `Code.string_to_quoted(File.read!(file), columns: true, token_metadata: true)`
   - Extract `defmodule` blocks.
3. For each module:
   - Resolve module name from `{:__aliases__, _, parts}` into a string (`Enum.map(parts, &Atom.to_string/1) |> Enum.join(".")`).
   - Track `alias` and `import` declarations at the module level.
   - Extract `def` and `defp` functions, recording name and arity.
   - For each function body, collect call nodes.

**Call Extraction**
- **Remote calls**: `{{:., _, [module_ast, fun]}, _, args}`.
  - Resolve `module_ast` to a module string:
    - `{:__aliases__, _, parts}` -> resolve with local alias table.
    - `__MODULE__` -> current module name.
- **Local calls**: `{:fun_name, meta, args}` where `is_list(args)`.
  - If local function exists in module, treat as local call.
  - If not, resolve against imported modules (see below).

**Alias Resolution**
Track `alias Mod` and `alias Mod, as: Alias` forms. Keep an `alias_map` of `%{"Alias" => "Full.Module"}`. Replace `{:__aliases__, _, [:Alias | rest]}` with the mapped full module + rest.

**Import Resolution**
Track `import Mod` with `only` / `except`. Maintain `imports` as:
```
%{
  "Full.Module" => %{only: MapSet of {fun, arity} | :all, except: MapSet}
}
```
When encountering a local call to `fun`:
- If exactly one imported module defines `fun` (by name, any arity) and is allowed by `only/except`, resolve to that module.
- If more than one candidate, record an `:ambiguous_call` for that edge (later surfaced in flow validation if needed).

**Why not parse arity strictly?**
The config path does not include arity, so validation only requires a name match. Internally, we still track arity so debug output can be precise and future extensions can become arity-aware.

### 3) Validate Each Flow
For each flow:
1. **Module existence**: confirm each `step.module` is in `index.modules`.
2. **Function existence**: confirm `step.function` exists in `index.functions[step.module]` (any arity).
3. **Call chain**: for each adjacent pair `A -> B`:
   - For all arities of `A.function`, check `calls[{A.module, A.function, arity}]` contains any `{B.module, B.function, _}`.
   - If none, record `:missing_edge`.

### 4) Reporting & Exit Codes
- `mix priv_signal.validate` prints:
  - Overall status
  - Per-flow status
  - Detailed errors
- Exit `0` if all flows pass; non-zero if any fail.

### 5) Integration with `mix priv_signal.score`
Modify `Mix.Tasks.PrivSignal.Score.run/1` to run validation immediately after config load and before diff retrieval. Fail fast on errors.

## Observability & Reliability
### Telemetry
Emit minimal, structured telemetry to support deterministic CI diagnostics:
- `[:priv_signal, :validate, :index]` with:
  - `duration_ms`
  - `file_count`, `module_count`, `function_count`, `call_count`, `ambiguous_count`
  - `ok` and `error_count` (when failing)
- `[:priv_signal, :validate, :run]` with:
  - `duration_ms`
  - `flow_count`, `status`, `error_count`, `ambiguous_count`
  - `ok`

### Logging
Use `Logger` at appropriate levels:
- `debug`: start of index build and validation run with counts.
- `info`: successful index build and validation summary.
- `warning`: ambiguous import/call candidates detected.
- `error`: index build or validation failure summaries.

### Reliability
- Retry strategy: none (all operations are local and deterministic); fail fast on parse or validation errors.
- Timeout behavior: no explicit timeouts; validation is bounded by parsing and in-memory traversal.
- Graceful degradation: dynamic dispatch and non-resolvable calls are skipped; ambiguous imports are reported as errors, but validation continues to surface all failing edges.

## Sample Code (Illustrative)
```elixir
defmodule PrivSignal.Validate do
  def run(config) do
    index = PrivSignal.Validate.Index.build()
    results = Enum.map(config.flows, &validate_flow(&1, index))
    {status, errors} = summarize(results)
    {status, results, errors}
  end
end
```

## Alternatives Considered
### 1) BEAM + `:xref` Call Graph
**Pros**
- Works on compiled code; resolves macros and aliases.
- Fast for large codebases.

**Cons**
- Call edges may be optimized away (inlining), causing false negatives.
- Requires compilation and debug info settings.
- Harder to map to source for precise error messages.

### 2) BEAM Abstract Code (`:beam_lib`)
**Pros**
- Structured, compiler-produced representation.
- Avoids source parsing.

**Cons**
- Requires compiled BEAM files.
- Can still miss or transform source-level call edges.
- Debug info may be stripped in CI, making it unreliable.

### 3) External Static Analysis Tools (Dialyzer, ElixirSense)
**Pros**
- Rich analysis.

**Cons**
- Adds dependencies and complexity.
- Not necessary for the PRD requirements.

### Recommended Approach vs Alternatives
AST-based indexing from source is deterministic, avoids compilation artifacts, and closely matches developer intent. It’s the most direct way to validate “A calls B” as written in the code.

## Tradeoffs and Limitations
- Dynamic dispatch (`apply/3`, `Module.function(...)` computed at runtime) is not validated.
- Macros that generate calls will not appear unless explicitly in the source AST (but the macro invocation itself will be present).
- Complex import scenarios may be ambiguous; ambiguous local calls are reported as such.

These align with the PRD’s constraint of deterministic, statically verifiable behavior.

## Performance
- One-time parse across `elixirc_paths` only.
- 12–20 flows validate in O(flows * path_length * arities) against an in-memory index.
- Expected to complete within CI target (<30s) for typical repos.
- Memory expectations: index size scales with module/function/call counts; target is to remain within typical CI memory budgets (well under a few hundred MB for mid-sized repos).

## Testing Strategy
**Unit**
- AST extraction for:
  - def/defp with guards
  - remote calls (`Mod.fun/arity`)
  - local calls
  - alias resolution
  - import resolution with `only` / `except`

**Integration**
- Build a minimal fixture module tree in `test/fixtures/validate` (or temp dir) and ensure:
  - Flow passes when calls exist.
  - Missing module/function/edge produces precise errors.

**Score Task Integration**
- Add tests to ensure `mix priv_signal.score` fails fast on validation errors.

## Open Questions (to Resolve During Implementation)
- Final mix task name (`priv_signal.validate` is recommended for consistency).
- How strict alias/import resolution should be in edge cases.
- Whether to include `.exs` files under `elixirc_paths` in test env.

## Implementation Plan (High-Level)
1. Implement `PrivSignal.Validate.Index` and AST utilities.
2. Implement `PrivSignal.Validate` orchestration and error formatting.
3. Add `Mix.Tasks.PrivSignal.Validate`.
4. Wire validation into `Mix.Tasks.PrivSignal.Score`.
5. Add unit + integration tests.
