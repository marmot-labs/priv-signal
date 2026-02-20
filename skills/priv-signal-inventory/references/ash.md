# Ash Reference

Use this guide when repository resources are defined with Ash.

## Detect Ash Usage
Look for:
- `use Ash.Resource`
- `attributes do` blocks
- `relationships do` blocks
- deps such as `:ash`, `:ash_postgres`, `:ash_ecto`

## What To Extract
Primary sources:
- `attributes do` entries like `attribute :email, :string`
- `relationships do` entries like `belongs_to :user, ...` (implies linkable identifier)

Secondary sources:
- `identities do` for stable identifiers
- `calculations do` and `aggregates do` for inferred/profiling attributes

## Candidate Field Heuristics
Class hints:
- `direct_identifier`: `email`, `name`, `first_name`, `last_name`, `phone`, `address`, `ssn`, `passport`, `dob`, `ip`
- `persistent_pseudonymous_identifier`: `_id` fields, `device_id`, `account_id`, `customer_id`, stable `token`
- `behavioral_signal`: activity/event/history fields and counters
- `inferred_attribute`: calculated scores, probabilities, labels, ranking/segment outputs
- `sensitive_context_indicator`: health/protected-context terms (`health`, `disability`, `religion`, `race`, `ethnicity`, `political`, `biometric`, etc.)

Sensitivity hints (`sensitive: true`):
- true for `sensitive_context_indicator`
- true for credentials/secrets, government IDs, payment details, biometric and protected-context fields
- false by default for most stable IDs unless context strongly suggests elevated sensitivity

## Exclusions
Usually exclude:
- framework lifecycle fields (`inserted_at`, `updated_at`)
- purely operational metadata without privacy meaning

Keep if semantic meaning implies PRD despite framework-generated origin.

## Construction Rules
For each included field produce:
- `scope.module`: Ash resource module name
- `scope.field`: attribute/relationship field name
- `key`: stable snake_case (example: `account_email`)
- `label`: title-cased field label

Deduplicate by `scope.module` + `scope.field`.

## Example Mapping
Ash attribute:
- `attribute :engagement_score, :float` in `MyApp.Accounts.Profile`

PRD node:

```yaml
- key: profile_engagement_score
  label: Profile Engagement Score
  class: inferred_attribute
  sensitive: false
  scope:
    module: MyApp.Accounts.Profile
    field: engagement_score
```
