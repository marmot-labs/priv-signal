# PRD: Rubric V2 (Categorical, Non-Numeric)

## Overview
Rubric V2 replaces point-based scoring with a categorical decision model based on event presence.

Decision order:
1. If semantic diff is empty -> `NONE`
2. Else if any `HIGH` event exists -> `HIGH`
3. Else if any `MEDIUM` event exists -> `MEDIUM`
4. Else -> `LOW`

No numeric points are calculated or emitted.

## Problem
Current V1 scoring is additive and weight-driven. Reviewers need a clearer, easier-to-explain model where risk maps directly to recognizable event categories.

## Goals
- Make score output immediately understandable from event category presence.
- Keep scoring deterministic and explainable.
- Remove numeric point math from score output and logic.
- Ensure CI behavior remains stable and predictable.
- Completely remove the original V1 scoring codepath and configuration from the score command.

## Non-Goals
- Reworking scan/infer internals beyond required diff schema support.
- Introducing policy exit-code changes in this phase.
- Preserving backward compatibility with V1 scoring artifacts or score runtime behavior.

## Users
- Developers running CI and local checks.
- Reviewers interpreting privacy risk quickly.
- Privacy/security engineers auditing rationale.

## Functional Requirements
- `mix priv_signal.score` consumes semantic diff JSON and applies categorical rubric.
- Score values are exactly: `NONE | LOW | MEDIUM | HIGH`.
- Empty diff returns `NONE`.
- Any single `HIGH`-mapped event returns `HIGH`.
- If no `HIGH`, any single `MEDIUM`-mapped event returns `MEDIUM`.
- If diff is non-empty and no `HIGH`/`MEDIUM` events are present, return `LOW`.
- Output includes matched triggering events (rule/event ids) for explainability.
- No `points` field is produced.
- No runtime/config fallback to V1 scoring exists after this feature is implemented.

## Rubric V2 Event Model
Rubric V2 is based on explicit event categories emitted by semantic diff.

### HIGH events (any one triggers HIGH)
- New external PII egress path (a *new* liveview or controller appears where PII usage of any sensitivity is present)
- New high-sensitivity PII exposure across a trust boundary. (high sensitivity pii appears in an external node)
- Protective transform removal on an external path. 
- New third-party/vendor destination for high-sensitivity PII.

### MEDIUM events (if no HIGH; any one triggers MEDIUM)
- New internal PII sink/transfer path.
- PII medium sensitivity appears in an existing path.
- Boundary tier increase (internal -> external) for medium sensitivity.
- Confidence increase coupled with exposure expansion.

### LOW events
- Any remaining non-empty semantic changes that are privacy-relevant but do not match HIGH or MEDIUM categories, things like low sensitivity PII apearing. 

## Expected Semantic Diff Changes
Rubric V2 likely requires semantic diff output changes so score can classify without inference from flow proxies.

Required direction:
- Emit node/edge-native change records (not only flow-proxy changes).
- Emit normalized event type/category fields directly in diff output.
- Include boundary, destination/vendor identity, sensitivity, PII category delta, and transform-change metadata.
- Include stable event ids for deterministic reason reporting.

## Output Contract (Score)
Proposed output:
- `version`
- `score` (`NONE|LOW|MEDIUM|HIGH`)
- `reasons` (deterministic list of triggering event/rule ids)
- `summary` (counts by severity category/event type)

Not included:
- `points`

## Acceptance Criteria
- Given empty diff, score is `NONE`.
- Given non-empty diff with >=1 HIGH event, score is `HIGH`.
- Given no HIGH and >=1 MEDIUM event, score is `MEDIUM`.
- Given non-empty diff with no HIGH/MEDIUM events, score is `LOW`.
- Repeated runs on identical diff/config produce byte-stable output ordering.
- Given any attempt to use legacy V1 score inputs/config, score fails with a clear unsupported-contract error.

## Status Checklist (2026-02-15)
- [x] `RV2-FR-001` score consumes semantic diff and outputs valid category (`test/mix/tasks/priv_signal_v2_e2e_test.exs`)
- [x] `RV2-FR-002` empty diff -> `NONE` (`test/priv_signal/score/decision_order_v2_test.exs`)
- [x] `RV2-FR-003` any HIGH event -> `HIGH` (`test/priv_signal/score/decision_order_v2_test.exs`)
- [x] `RV2-FR-004` no HIGH + any MEDIUM -> `MEDIUM` (`test/priv_signal/score/decision_order_v2_test.exs`)
- [x] `RV2-FR-005` non-empty without HIGH/MEDIUM -> `LOW` (`test/priv_signal/score/decision_order_v2_test.exs`)
- [x] `RV2-FR-006` deterministic triggering reasons emitted (`test/priv_signal/score/determinism_v2_property_test.exs`)
- [x] `RV2-FR-007` no `points` in output (`test/priv_signal/score/output_json_v2_test.exs`)
- [x] `RV2-FR-008` diff emits node/edge-native metadata (`test/priv_signal/diff/semantic_v2_test.exs`)
- [x] `RV2-FR-009` stable `event_id` semantics (`test/priv_signal/diff/event_id_determinism_test.exs`)
- [x] `RV2-FR-010` repeated runs are byte-stable (`test/priv_signal/diff/contract_v2_test.exs`, `test/priv_signal/score/determinism_v2_property_test.exs`)
