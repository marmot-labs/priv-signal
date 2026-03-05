---
name: priv-signal-inventory
description: Generate an initial PrivSignal inventory config by inspecting an Elixir repository, detecting how schemas are defined, and extracting likely privacy-relevant fields into `priv_signal.yml`. Use when asked to bootstrap/update PrivSignal config, inventory PII/PRD fields, or map sensitive data from Ecto/Ash models.
---

# PrivSignal Inventory

## Goal
Create a high-confidence first-pass `priv_signal.yml` in the repository root.

Use repository code to infer likely PRD nodes, especially from Ecto and Ash schema definitions.

## Required Output Contract
Write canonical config filename `priv_signal.yml` (underscore).

If `priv_signal.yml` already exists, write `priv_signal.candidate.yml` unless explicitly asked to overwrite the existing file.

Emit this minimum structure:

```yaml
version: 1
prd_nodes: []
matching:
  aliases: {}
  split_case: true
  singularize: true
  strip_prefixes: []
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
    wrapper_modules: []
    wrapper_functions: []
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
6. Build `matching.aliases` with a serious best-effort pass:
   - map derived field tokens back to canonical PRD scope fields (for example `invitee_email -> email`, `submitted_emails -> email`)
   - only include aliases you can justify from repository naming patterns
   - avoid speculative aliases without direct code evidence
7. Discover DB wrapper usage and populate:
   - `scanners.database.wrapper_modules`
   - `scanners.database.wrapper_functions`
8. Write `priv_signal.yml` at repo root.
9. If PrivSignal mix tasks are available, run `mix priv_signal.validate` and fix schema issues.
10. Report uncertain classifications and what to review manually.

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

## Matching Alias Discovery Rules
Build aliases from observed naming drift between code tokens and PRD fields.

Look for code tokens in:
- map keys and keyword keys in logging/http/controller/telemetry payloads
- variable names and attrs maps (`*_email`, `*_emails`, `*_id`, `submitted_*`, `invitee_*`, `student_*`)
- params/body/payload transformation code near sinks

Map to canonical PRD field only when one of these holds:
- exact singular/plural relationship (`emails -> email`)
- clear prefix wrapper (`submitted_email -> email`)
- clear domain synonym already used in codebase (`invitee_email -> email`, `learner_id -> user_id`)

Alias safety rules:
- key and value must be snake_case strings
- alias target must exist in `prd_nodes.scope.field`
- prefer precision over recall; keep alias list reviewable and conservative
- dedupe and sort aliases deterministically by key

## Database Wrapper Discovery Rules
Populate DB wrappers by finding non-Repo functions that call `Repo.*` and are called from app code.

Discovery pass:
- identify `Repo` modules from `repo_modules` plus common `*.Repo` modules
- scan for local and namespaced function definitions that call write/read operations:
  - reads: `get`, `get_by`, `one`, `all`, `preload`
  - writes: `insert`, `update`, `delete`, `insert_all`, `update_all`, `delete_all`
- collect wrapper module names and function names/arity used as indirection points

Population rules:
- `wrapper_modules`: fully qualified module names containing wrapper functions
- `wrapper_functions`: function name and/or `name/arity` when clear (`append_step`, `append_step/2`)
- include only wrappers with direct evidence of `Repo.*` usage
- dedupe and sort both lists deterministically

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

Also sort:
- `matching.aliases` by alias key
- `scanners.database.repo_modules`, `wrapper_modules`, and `wrapper_functions` alphabetically

## Safety And Quality
Do not include literal production data or secrets.

Treat output as a candidate baseline. Always call out low-confidence fields and ask for human review on:
- ambiguous inferred attributes
- context-dependent sensitive flags
- legacy or generated fields with unclear meaning
- alias mappings that are plausible but not strongly evidenced
- wrapper functions that may be utility-only and not true data persistence boundaries
