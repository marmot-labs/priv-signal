# Ecto Reference

Use this guide when repository schemas are defined with Ecto.

## Detect Ecto Usage
Look for:
- `use Ecto.Schema`
- `schema "..." do`
- `embedded_schema do`
- deps `:ecto` or `:ecto_sql` in `mix.exs`

## What To Extract
Primary sources:
- `field :name, :type`
- `belongs_to :user, ...` (implies foreign key like `user_id`)
- `embeds_one` / `embeds_many`

Secondary sources:
- changesets (`cast/4`, `validate_required/3`) for fields that indicate public/sensitive data
- migrations for columns that may not be represented in current schema modules

## Candidate Field Heuristics
Map by field token and context.

Class hints:
- `direct_identifier`: `email`, `first_name`, `last_name`, `full_name`, `phone`, `address`, `ssn`, `passport`, `license`, `dob`, `birth`, `biometric`, `ip`
- `persistent_pseudonymous_identifier`: suffix `_id`, `account_id`, `device_id`, `session_id`, `external_id`, stable `token`
- `behavioral_signal`: `event`, `click`, `view`, `search`, `time_spent`, `duration`, `location_history`, `purchase_event`
- `inferred_attribute`: `score`, `prediction`, `probability`, `risk`, `segment`, `classification`, `affinity`, `likelihood`
- `sensitive_context_indicator`: `health`, `diagnosis`, `treatment`, `religion`, `race`, `ethnicity`, `disability`, `sexual`, `political`, `financial_distress`

Sensitivity hints (`sensitive: true`):
- always true for `sensitive_context_indicator`
- true for government IDs, credentials/secrets, payment or account numbers, biometric signals, exact address/contact details where high risk
- often false for plain stable IDs (`user_id`) unless context shows elevated risk

## Exclusions
Usually exclude unless context proves privacy relevance:
- `id`
- `inserted_at`, `updated_at`, `deleted_at`
- versioning/locking metadata

Keep `id` if schema uses a non-default identifier with real linkability semantics.

## Construction Rules
For each included field produce:
- `scope.module`: module containing the Ecto schema
- `scope.field`: field atom name as string
- `key`: stable snake_case (example: `user_email`, `order_device_id`)
- `label`: title-cased field label

Deduplicate by `scope.module` + `scope.field`.

## Example Mapping
Ecto schema field:
- `field :email, :string` in `MyApp.Accounts.User`

PRD node:

```yaml
- key: user_email
  label: User Email
  class: direct_identifier
  sensitive: true
  scope:
    module: MyApp.Accounts.User
    field: email
```
