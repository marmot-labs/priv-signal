# Rubric V2 Rollout Runbook

## Scope
One-way cutover from legacy score contracts to Rubric V2 (`diff.version=v2`, `score.version=v2`).

## Preconditions
- Phase 0-5 tests are green.
- `mix compile --warnings-as-errors` is green.
- `mix format --check-formatted` is green.
- CI jobs consume score output without `points`.

## Rollout Steps
1. Merge Rubric V2 changes to main.
2. Update CI templates to run:
   - `mix priv_signal.scan`
   - `mix priv_signal.diff --base <ref> --format json --output <path>`
   - `mix priv_signal.score --diff <path> --output <path>`
3. Verify score artifacts in CI:
   - `version == "v2"`
   - `score` in `NONE|LOW|MEDIUM|HIGH`
   - `summary.events_*` keys present
   - `points` key absent
4. Monitor first rollout window:
   - score task failures
   - strict-mode unknown taxonomy failures
   - category distribution drift (`HIGH|MEDIUM|LOW|NONE`)

## Break-Glass Guidance
- There is no runtime fallback to v1 scoring.
- If downstream systems still require `points`, patch those consumers immediately to use:
  - `score`
  - `summary.events_total/events_high/events_medium/events_low`
  - `reasons[]`

## Post-Rollout Validation
- Re-run:
  - `mix test`
  - `mix compile --warnings-as-errors`
  - `mix format --check-formatted`
- Run smoke flow on main branch:
  - `mix priv_signal.scan`
  - `mix priv_signal.diff --base <ref> --format json --output tmp/privacy_diff_v2.json`
  - `mix priv_signal.score --diff tmp/privacy_diff_v2.json --output tmp/priv_signal_score_v2.json`
