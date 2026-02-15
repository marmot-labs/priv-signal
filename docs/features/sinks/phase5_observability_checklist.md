# Phase 5 Observability Checklist

References
- `docs/features/sinks/prd.md`
- `docs/features/sinks/fdd.md`
- `docs/features/sinks/plan.md`

## Dashboard Widgets
- [ ] Scan run duration p50/p95 from `[:priv_signal, :scan, :run]`
- [ ] Scan error rate from `[:priv_signal, :scan, :run]` (`error_count` / `file_count`)
- [ ] Findings by scanner category from `[:priv_signal, :scan, :category, :run]`
- [ ] Candidate emits by `role_kind` and `node_type` from `[:priv_signal, :scan, :candidate, :emit]`

## Alerts
- [ ] Alert: parse+timeout error rate > 2% for 3 consecutive CI windows
- [ ] Alert: category findings drop by >80% week-over-week for active repos
- [ ] Alert: strict mode failures spike above baseline

## Cardinality Guardrails
- [ ] Do not tag metrics with file paths or module names
- [ ] Restrict tags to enum-like values (`category`, `role_kind`, `node_type`, `strict_mode`)

## Rollout Verification
- [ ] Validate telemetry presence in dev CI runs for all five category scanners
- [ ] Validate dashboard values against fixture-run expectations
- [ ] Validate alert firing by controlled failure injection (parse error fixture)
