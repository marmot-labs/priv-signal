# PrivSignal

PrivSignal is a tool that detects privacy drift in Elixir codebases during CI/CD workflows. It scans an Elixir codebase against a versioned privacy catalog, writes a deterministic lockfile, compares pull request lockfiles against the base branch, and emits an explainable risk label: `NONE`, `LOW`, `MEDIUM`, or `HIGH`.

The primary use case is PR review. PrivSignal helps surface when a change introduces new handling of personal data, expands exposure to logs or telemetry, changes boundaries such as HTTP or controller responses, or otherwise invalidates privacy assumptions your team has already documented.

PrivSignal is advisory. It is not a compliance engine, does not replace legal or privacy review, and does not decide whether a change is legally acceptable. It provides an explainable signal that tells reviewers when a change deserves a closer look.

## Why PrivSignal

Privacy Impact Assessments often drift away from the code they describe. Normal development can gradually introduce new personal data handling, new sinks, new external transfers, or new exposure paths before anyone realizes the privacy baseline has changed.

PrivSignal brings that reassessment signal into the development workflow. It uses explicit, human-authored configuration and deterministic artifacts so privacy-relevant changes can be reviewed at pull request time.

## What It Does

PrivSignal supports three related workflows:

- Build a project-specific catalog of privacy-relevant data attributes in `priv_signal.yml`.
- Run `mix priv_signal.scan` to generate `priv_signal.lockfile.json`, a deterministic baseline artifact that captures usage of privacy-relevant data attributes across a codebase.
- Run `diff` and `score` in pull request workflows to compare the PR branch against the base branch and produce an explainable privacy risk score.

The same scanning primitives are also useful outside PR scoring. You can run `mix priv_signal.scan` as a repository audit to find privacy-relevant touchpoints such as logging, telemetry, controller responses, outbound HTTP calls, database access, and LiveView exposure patterns.

## Requirements

- Elixir `~> 1.18`
- Erlang/OTP compatible with your Elixir version
- Git, when comparing lockfiles across refs

## Installation

PrivSignal can be used from source as a Mix dependency:

```elixir
def deps do
  [
    {:priv_signal, git: "https://github.com/marmot-labs/priv-signal.git"}
  ]
end
```

Then fetch and compile dependencies:

```bash
mix deps.get
mix compile
```

## Quick Start

### 1. Create and validate a catalog

Generate a starter config:

```bash
mix priv_signal.init
```

Validate the catalog:

```bash
mix priv_signal.validate
```

### 2. Generate the baseline lockfile

Run the scanner on the default branch and commit the generated baseline:

```bash
mix priv_signal.scan
git add priv_signal.yml priv_signal.lockfile.json
git commit -m "add PrivSignal baseline"
```

### 3. Score a pull request locally

```bash
mix priv_signal.scan --json-path tmp/pr.lockfile.json
mix priv_signal.diff \
  --base origin/main \
  --candidate-path tmp/pr.lockfile.json \
  --artifact-path priv_signal.lockfile.json \
  --format json \
  --output tmp/privacy_diff.json
mix priv_signal.score --diff tmp/privacy_diff.json --output tmp/priv_signal_score.json
```

If you want `scan` to fail on parse or scan errors, use strict mode:

```bash
mix priv_signal.scan --strict --json-path tmp/pr.lockfile.json
```

## How It Works

```mermaid
flowchart TD
    A[Author priv_signal.yml] --> B[Validate catalog]
    B --> C[Run scan on main branch]
    C --> D[Commit priv_signal.lockfile.json as baseline]
    D --> E[Open pull request]
    E --> F[CI runs scan on PR branch]
    F --> G[Diff PR lockfile vs base branch lockfile]
    G --> H[Score semantic diff]
    H --> I[Review score and evidence]
```

Typical workflow:

1. Create `priv_signal.yml` to describe the privacy-relevant fields and modules in your system.
2. Run `mix priv_signal.validate` to confirm the config is structurally valid.
3. Run `mix priv_signal.scan` on your default branch to generate `priv_signal.lockfile.json`.
4. Commit both files. The lockfile becomes the baseline artifact PrivSignal compares against in future PRs.
5. In CI for a pull request, run `mix priv_signal.scan` again to generate a fresh lockfile for the proposed code.
6. Run `mix priv_signal.diff --base <target-branch-ref>` to compute the semantic privacy diff between the committed base artifact and the PR artifact.
7. Run `mix priv_signal.score --diff ...` to turn that diff into a deterministic privacy risk score and summary.

## Configuration

PrivSignal uses a repository-root `priv_signal.yml` file as the source of truth for the privacy catalog. At minimum, define `prd_nodes` that map privacy-relevant fields to the Elixir modules where they live.

Example:

```yaml
version: 1

prd_nodes:
  - key: user_email
    label: User Email
    class: direct_identifier
    sensitive: true
    scope:
      module: MyApp.Accounts.User
      field: email

  - key: user_id
    label: User ID
    class: persistent_pseudonymous_identifier
    sensitive: false
    scope:
      module: MyApp.Accounts.User
      field: user_id

  - key: engagement_score
    label: Engagement Score
    class: inferred_attribute
    sensitive: false
    scope:
      module: MyApp.Analytics.UserProfile
      field: engagement_score

scanners:
  logging:
    enabled: true
    additional_modules: []
  http:
    enabled: true
    additional_modules: []
    internal_domains: []
    external_domains: []
  controller:
    enabled: true
    additional_render_functions: []
  telemetry:
    enabled: true
    additional_modules: []
  database:
    enabled: true
    repo_modules: []
  liveview:
    enabled: true
    additional_modules: []
```

The generated `priv_signal.lockfile.json` is not intended to be hand-edited. Treat it as a checked-in baseline artifact produced by `mix priv_signal.scan`.

## Commands

`mix priv_signal.init`

- Creates a starter `priv_signal.yml` in the current directory.

`mix priv_signal.validate`

- Validates `priv_signal.yml` against the current codebase and config schema.

`mix priv_signal.scan`

- Runs deterministic static analysis and writes `priv_signal.lockfile.json` by default.
- Common flags: `--json-path PATH`, `--strict`, `--quiet`, `--timeout-ms N`, `--max-concurrency N`.

`mix priv_signal.diff --base <ref>`

- Compares the current or supplied candidate lockfile against the lockfile on the base ref.
- Supports `--candidate-path`, `--candidate-ref`, `--artifact-path`, `--format`, `--include-confidence`, `--strict`, and `--output`.

`mix priv_signal.score --diff <path>`

- Consumes a semantic diff JSON artifact and writes a deterministic score JSON artifact.
- Supports `--output`, `--quiet`, and `--help`.

## What `scan` Looks For

PrivSignal currently scans for privacy-relevant usage across these categories:

- Logging sinks such as `Logger` and configured wrappers.
- Outbound HTTP calls and boundary changes.
- Controller response exposure.
- Telemetry and analytics exports.
- Database reads and writes.
- LiveView assigns, render paths, and event exposure.

This is why `scan` is useful both as the first step in the PR scoring workflow and as a standalone audit tool.

## Understanding Results

PrivSignal reports privacy-relevant changes through stable detection and scoring categories:

- `PS-SCAN-*`: scanner-level detection classes from `mix priv_signal.scan`.
- `PS-DIFF-*`: semantic privacy diff classes from `mix priv_signal.diff`.
- `PS-SCORE-*`: score rubric classes from `mix priv_signal.score`.

The final PR score is selected from the highest-risk detected event:

- `NONE` when there are no privacy-relevant events.
- `HIGH` when any high-class event exists.
- `MEDIUM` when there are no high-class events but at least one medium-class event exists.
- `LOW` when privacy-relevant events exist but do not meet the medium or high criteria.

See [SCORING.md](SCORING.md) for scoring definitions and examples. See [docs/classification_registry.md](docs/classification_registry.md) for the stable scan, diff, and score registry.

## CI Usage

```yaml
name: PrivSignal

on:
  pull_request:

jobs:
  priv_signal:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: erlef/setup-beam@v1
        with:
          elixir-version: "1.18"
          otp-version: "27"

      - run: mix deps.get
      - run: mix priv_signal.validate
      - run: mix priv_signal.scan --json-path tmp/pr.lockfile.json
      - run: mix priv_signal.diff --base origin/main --candidate-path tmp/pr.lockfile.json --artifact-path priv_signal.lockfile.json --format json --output tmp/privacy_diff.json
      - run: mix priv_signal.score --diff tmp/privacy_diff.json --output tmp/priv_signal_score.json
```

This assumes `priv_signal.lockfile.json` is already committed on the base branch.

## Inventory Bootstrap Skill

This repository includes an installable AI coding skill at [skills/priv-signal-inventory/SKILL.md](skills/priv-signal-inventory/SKILL.md) that helps bootstrap `priv_signal.yml` for Elixir codebases. It is designed for Codex- and Claude Code-style agent workflows and can inspect local schemas, infer likely PRD nodes, and produce a high-confidence first pass of the catalog.

Use it when the hardest part of adoption is building the initial privacy catalog. It can significantly reduce the manual effort required to identify candidate modules, fields, aliases, and database wrapper boundaries before you validate and refine the file yourself.

## Documentation

- [SCORING.md](SCORING.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Classification registry](docs/classification_registry.md)
- [Core PRD](docs/features/core/prd.md)
- [Semantic diff PRD](docs/features/semantic_diff/prd.md)
- [Scoring PRD](docs/features/scoring/prd.md)
- [Release notes](docs/release_notes.md)

## Development

Run the standard project checks:

```bash
mix deps.get
mix compile
mix test
mix format
```

Tests use ExUnit and live under `test/`.

## Contributing

Issues and pull requests should include:

- A short description of the privacy or CLI behavior being changed.
- Tests, or a note explaining why tests are not applicable.
- Any changes needed to `priv_signal.yml`, generated lockfile behavior, or CI usage.

Keep changes focused and avoid committing secrets or sensitive generated configuration.

## Security and Privacy Notes

- Set model credentials with environment variables such as `PRIV_SIGNAL_MODEL_API_KEY`.
- Do not commit secrets, real personal data, or generated config containing sensitive values.
- Treat `priv_signal.yml` and `priv_signal.lockfile.json` as reviewable privacy metadata.
- PrivSignal output is advisory and should be reviewed alongside the code change.

## Getting Help

Open a GitHub issue with the command you ran, the relevant `priv_signal.yml` excerpt, and the error or generated output. Do not include secrets or sensitive personal data.

## License

This project is licensed under the terms of the [MIT License](LICENSE).
