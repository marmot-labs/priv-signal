# Repository Guidelines

PrivSignal is an Elixir CLI tool that operationalizes PIA reassessment triggers in GitHub CI/CD workflows for Elixir-based systems.

## Project Structure & Module Organization

- `lib/` holds application code. The main entrypoint is `lib/priv_signal.ex`, with supporting modules under `lib/priv_signal/` (config, runtime, telemetry, etc.).
- `test/` contains ExUnit tests. Most are grouped under `test/priv_signal/` with a few top-level tests like `test/priv_signal_test.exs`.
- `docs/` contains product and architecture notes (`prd.md`, `plan.md`, `fdd.md`). See `docs/prd.md` and `docs/fdd.md` for the core product and functional design references.
- `priv-signal.yml` (repo root, created via `mix priv_signal.init`) is the configuration source of truth.

## Build, Test, and Development Commands

- `mix deps.get`: Fetch dependencies.
- `mix compile`: Compile the project.
- `mix test`: Run the full ExUnit test suite.
- `mix format`: Apply Elixir formatting according to `.formatter.exs`.
- `mix priv_signal.init`: Generate a starter `priv-signal.yml` config.
- `mix priv_signal.score --base origin/main --head HEAD`: Score a diff using the configured model.

## Coding Style & Naming Conventions

- Use `mix format` for formatting; follow standard Elixir conventions.
- Modules are namespaced under `PrivSignal.*` and live in `lib/priv_signal/*.ex`.
- Files use snake_case, tests end with `_test.exs` and live in `test/`.

## Testing Guidelines

- Framework: ExUnit (see `test/test_helper.exs`).
- Naming: test files use `*_test.exs`, with descriptive test names.
- Run tests with `mix test`. No explicit coverage target is defined.

## Commit & Pull Request Guidelines

- Commit history is small and does not show a strict convention. Use short, imperative summaries (e.g., “add telemetry event”) and keep commits focused.
- PRs should include a brief description, testing notes (e.g., `mix test`), and any config changes to `priv-signal.yml` if behavior is affected.

## Security & Configuration Tips

- Set model credentials via environment variables like `PRIV_SIGNAL_MODEL_API_KEY` and related settings documented in `README.md`.
- Do not commit secrets or generated config containing sensitive values.
