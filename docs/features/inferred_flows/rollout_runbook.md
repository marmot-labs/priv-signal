# Proto Flow Inference v1 Rollout Runbook

## Scope
Operational rollout for inferred `flows` in `mix priv_signal.infer` output.

## Feature Flag
- Env var: `PRIV_SIGNAL_INFER_PROTO_FLOWS_V1`
- Default: `true`
- Kill-switch: set to `false` to emit `flows: []` while preserving node inventory.

## Canary Plan
1. Enable in 3 representative repos (controller-heavy, LiveView-heavy, mixed).
2. Run infer at least 20 times per repo in CI.
3. Verify:
- zero infer failures
- deterministic `flows_hash` across repeated runs on unchanged commits
- no large p95 duration regression (>10%).

## Metrics and Alerts
Telemetry events:
- `[:priv_signal, :infer, :run, :start]`
- `[:priv_signal, :infer, :flow, :build]`
- `[:priv_signal, :infer, :run, :stop]`
- `[:priv_signal, :infer, :output, :write]`

Suggested alerts:
- infer error rate > 2% over 15m
- infer run p95 regression > 10% versus 7-day baseline
- unexpected determinism drift (`flows_hash` mismatch on unchanged commit)

## Rollback
1. Set `PRIV_SIGNAL_INFER_PROTO_FLOWS_V1=false` in CI job environment.
2. Re-run `mix priv_signal.infer` and confirm `flow_count == 0`.
3. Keep node inventory in place for downstream compatibility.

## Verification Checklist
- [ ] Flag enabled path verified (`flow_count > 0` on known fixtures)
- [ ] Kill-switch path verified (`flow_count == 0`)
- [ ] Telemetry events observed in AppSignal/OpenTelemetry sink
- [ ] No PII values in logs/telemetry metadata
