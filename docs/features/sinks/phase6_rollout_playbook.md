# Phase 6 Rollout Playbook

References
- PRD: `docs/features/sinks/prd.md`
- FDD: `docs/features/sinks/fdd.md`
- Plan: `docs/features/sinks/plan.md`

## Canary Rollout
1. Enable all Phase 4 scanners in one low-risk repository.
2. Run `mix priv_signal.scan` in CI for at least 3 consecutive runs.
3. Compare role-kind distribution against fixture baseline.
4. Expand to 3-5 repositories after stable error rate and runtime.

## Metrics Watchlist
- `[:priv_signal, :scan, :run]`: duration, error_count, file_count.
- `[:priv_signal, :scan, :category, :run]`: duration/finding_count per category.
- `[:priv_signal, :scan, :candidate, :emit]`: role_kind/node_type counts.
- `[:priv_signal, :infer, :flow, :build]`: flow_count and boundary distribution.

## Kill Switch
- Disable categories with config toggles:
  - `scanners.http.enabled: false`
  - `scanners.controller.enabled: false`
  - `scanners.telemetry.enabled: false`
  - `scanners.database.enabled: false`
  - `scanners.liveview.enabled: false`
- Keep logging scanner enabled as baseline fallback.

## Rollback
1. Revert scanner config to logging-only enablement.
2. Re-run `mix priv_signal.scan --strict` to confirm baseline behavior.
3. Compare lockfile to prior logging-only artifact for determinism.
4. Keep infer schema at `1.2` (no schema rollback required).

## Incident Response
- Elevated parse/timeout errors:
  - lower concurrency (`--max-concurrency`), raise timeout (`--timeout-ms`), inspect malformed files.
- Unexpected finding volume spike:
  - disable high-noise categories first, inspect evidence signals, adjust overrides.
- Unexpected finding volume drop:
  - verify scanner enablement and telemetry emissions per category.
