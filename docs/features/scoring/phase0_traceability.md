# Scoring V1 Traceability Matrix

## FR to Implementation and Evidence

| FR | Implementation | Evidence |
|---|---|---|
| FR-001 | `Mix.Tasks.PrivSignal.Score` consumes `--diff` artifact and scores locally | `lib/mix/tasks/priv_signal.score.ex`, `test/mix/tasks/priv_signal_score_test.exs` |
| FR-002 | Deterministic path uses `PrivSignal.Score.Engine` only; no LLM in deterministic branch | `lib/priv_signal/score/engine.ex`, `test/priv_signal/score/engine_test.exs` |
| FR-003 | Buckets restricted to `NONE/LOW/MEDIUM/HIGH` | `lib/priv_signal/score/buckets.ex`, `test/priv_signal/score/buckets_test.exs` |
| FR-004 | `NONE` only when relevant changes are zero | `lib/priv_signal/score/buckets.ex`, `test/priv_signal/score/buckets_test.exs` |
| FR-005 | Weighted rules + config overrides | `lib/priv_signal/score/rules.ex`, `lib/priv_signal/config/schema.ex`, `test/priv_signal/score/config_overrides_test.exs` |
| FR-006 | Escalation floor rules for high-risk flow-proxy events | `lib/priv_signal/score/buckets.ex`, `test/priv_signal/score/buckets_test.exs` |
| FR-007 | Advisory is optional and non-fatal to deterministic fields | `lib/priv_signal/score/advisory.ex`, `lib/mix/tasks/priv_signal.score.ex`, `test/priv_signal/score/advisory_test.exs` |
| FR-008 | Output contract includes `score/points/summary/reasons` | `lib/priv_signal/score/output/json.ex`, `test/priv_signal/score/output_json_test.exs` |
| FR-009 | Summary includes required counters (with unavailable counters defaulted to 0 in V1) | `lib/priv_signal/score/engine.ex`, `test/priv_signal/score/engine_test.exs` |
| FR-010 | Input contract validates flow-proxy diff JSON (`version: v1`, `changes[]`) | `lib/priv_signal/score/input.ex`, `test/priv_signal/score/contract_phase0_test.exs` |
| FR-011 | Normalized scored item fields supported (`type`, `flow_id`, `change`, `rule_id`, `severity`, `details`) | `lib/priv_signal/score/input.ex`, `test/priv_signal/score/input_test.exs` |
| FR-012 | Contract failures are explicit, non-zero in score task | `lib/mix/tasks/priv_signal.score.ex`, `test/mix/tasks/priv_signal_score_test.exs` |
| FR-013 | `scoring.llm_interpretation.*` in schema/defaults | `lib/priv_signal/config.ex`, `lib/priv_signal/config/schema.ex`, `test/priv_signal/config_schema_test.exs` |
| FR-014 | Validated scoring weights/thresholds with defaults | `lib/priv_signal/config/schema.ex`, `test/priv_signal/config_schema_test.exs` |
| FR-015 | Score runs without model key when advisory disabled | `lib/mix/tasks/priv_signal.score.ex`, `test/mix/tasks/priv_signal_score_integration_test.exs` |
| FR-016 | Telemetry events for run/rule/advisory outcomes | `lib/mix/tasks/priv_signal.score.ex`, `lib/priv_signal/score/engine.ex`, `lib/priv_signal/score/advisory.ex`, `test/priv_signal/score/telemetry_test.exs` |
| FR-017 | Legacy `Risk.Assessor` removed from score path and score-mode config no longer requires `flows` | `lib/mix/tasks/priv_signal.score.ex`, `lib/priv_signal/config/schema.ex`, `test/mix/tasks/priv_signal_score_test.exs` |
| FR-018 | Determinism coverage for repeated runs/order variations | `test/priv_signal/score/determinism_property_test.exs` |
| FR-019 | Docs/help updated to `--diff` contract and deterministic scoring | `README.md`, `docs/features/scoring/{prd,fdd,plan}.md`, `lib/mix/tasks/priv_signal.score.ex` |
| FR-020 | Exit-code policy unchanged | `lib/mix/tasks/priv_signal.score.ex` |
| FR-021 | CI sequence documented as scan -> diff -> score (optional advisory after score) | `README.md`, `docs/features/scoring/prd.md` |

## Rule ID Catalog (Rubric V1)

- `R-HIGH-EXTERNAL-FLOW-ADDED`
- `R-MEDIUM-INTERNAL-FLOW-ADDED`
- `R-LOW-FLOW-REMOVED`
- `R-LOW-CONFIDENCE-ONLY`
- `R-HIGH-EXTERNAL-SINK-ADDED`
- `R-HIGH-EXTERNAL-SINK-CHANGED`
- `R-HIGH-BOUNDARY-EXITS-SYSTEM`
- `R-LOW-BOUNDARY-INTERNALIZED`
- `R-HIGH-PII-EXPANDED-HIGH-SENSITIVITY`
- `R-MEDIUM-PII-EXPANDED`
- `R-LOW-PII-REDUCED`
- `R-LOW-DEFAULT`

## Deterministic Sort Key

- Input changes: `{type, flow_id, change, stable(details)}`
- Reasons: `{severity_rank, rule_id, change_id}`
