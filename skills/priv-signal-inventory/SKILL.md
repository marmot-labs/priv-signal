---
name: priv-signal-inventory
description: Generate an initial PrivSignal inventory config by inspecting an Elixir repository, detecting how schemas are defined, and extracting likely privacy-relevant fields into `priv-signal.yml`. Use when asked to bootstrap/update PrivSignal config, inventory PII/PRD fields, or map sensitive data from Ecto/Ash models.
---

# PrivSignal Inventory

## Goal
Create a high-confidence first-pass `priv-signal.yml` in the repository root.

Use repository code to infer likely PRD nodes, especially from Ecto and Ash schema definitions.

## Required Output Contract
Write canonical config filename `priv-signal.yml` (hyphenated).

Do not use `priv_signal.yml` as the final output name because PrivSignal expects `priv-signal.yml`.

If `priv-signal.yml` already exists, write `priv-signal.candidate.yml` unless explicitly asked to overwrite the existing file.

Emit this minimum structure:

```yaml
version: 1
prd_nodes: []
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
flows: []
```

## Workflow
1. Detect how schemas are defined in the repository.
2. Load only the framework references you need: `references/ecto.md` and/or `references/ash.md`.
3. Extract candidate fields and map each field to a PRD node.
4. Classify nodes into allowed classes (`direct_identifier`, `persistent_pseudonymous_identifier`, `behavioral_signal`, `inferred_attribute`, `sensitive_context_indicator`).
5. Set `sensitive: true` for highly sensitive fields (health, financial account/payment, government identifiers, credentials/tokens, protected-context indicators).
6. Write `priv-signal.yml` at repo root.
7. If PrivSignal mix tasks are available, run `mix priv_signal.validate` and fix schema issues.
8. Report uncertain classifications and what to review manually.

## Framework Detection
Run lightweight detection before loading references.

Preferred checks:
- `mix.exs` deps for `:ecto`, `:ecto_sql`, `:ash`, `:ash_postgres`, `:ash_ecto`
- code patterns:
  - `use Ecto.Schema`
  - `use Ash.Resource`

If both frameworks are present, process both and merge deduplicated results.

If neither is found, fall back to best-effort inference from:
- migration files (`priv/repo/migrations`)
- plain structs used as domain models
- serializer/view modules that expose likely PRD fields

## Candidate Selection Rules
Include fields likely to be privacy-relevant. Prioritize names with these tokens:
- identity/contact: `email`, `name`, `first_name`, `last_name`, `phone`, `address`, `ip`, `ssn`, `dob`
- stable identifiers: `user_id`, `account_id`, `device_id`, `external_id`, `session_id`, `token`
- behavior/history: `event`, `click`, `view`, `search`, `duration`, `history`, `location`
- inferred/profiling: `score`, `prediction`, `probability`, `segment`, `classification`, `affinity`
- sensitive context: `health`, `diagnosis`, `disability`, `religion`, `race`, `ethnicity`, `political`, `biometric`, `financial_distress`

Usually exclude operational fields unless context indicates PRD:
- `inserted_at`, `updated_at`, `deleted_at`, `version`, `lock_version`

## Node Construction Rules
For each candidate field, emit one `prd_nodes` entry:
- `key`: stable snake_case identifier, usually `<module_subject>_<field>`
- `label`: readable title
- `class`: one of the five allowed classes
- `sensitive`: boolean
- `scope.module`: fully qualified module name
- `scope.field`: field name

Sort output deterministically by `scope.module`, then `scope.field`, then `key`.

Avoid duplicate entries for the same module+field.

## Safety And Quality
Do not include literal production data or secrets.

Treat output as a candidate baseline. Always call out low-confidence fields and ask for human review on:
- ambiguous inferred attributes
- context-dependent sensitive flags
- legacy or generated fields with unclear meaning
