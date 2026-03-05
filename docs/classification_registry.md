# PrivSignal Classification Registry

This registry defines stable, human-friendly identifiers for what PrivSignal can detect and score.

## Naming Convention

- `PS-SCAN-###`: scanner-level detection classes (AST findings in `mix priv_signal.scan`)
- `PS-DIFF-###`: semantic diff change classes (change events in `mix priv_signal.diff`)
- `PS-SCORE-###`: score rubric classes (risk outcomes in `mix priv_signal.score`)

Design intent:

- IDs are stable documentation anchors.
- IDs map to implementation rule IDs where available.
- IDs are not runtime-generated values.

---

## Scan Detection Registry (`PS-SCAN-*`)

| Registry ID | Scanner Category | Detects | Severity Label in Scan Markdown | Fictional Example |
|---|---|---|---|---|
| `PS-SCAN-001` | Logging | Logging call references PRD field directly (`direct_field_access`) | `HIGH`/`MEDIUM`/`LOW` based on classification+sensitivity | `Logger.info("email=#{user.email}")` in `AcmeWeb.AuthController` |
| `PS-SCAN-002` | Logging | Logging map/keyword keys match PRD tokens (`key_match`) | `HIGH`/`MEDIUM`/`LOW` | `Logger.metadata(email: email, user_id: id)` |
| `PS-SCAN-003` | Logging | Logging PRD container struct (`prd_container`) | `HIGH`/`MEDIUM`/`LOW` | `Logger.info(inspect(%Acme.User{} = user))` |
| `PS-SCAN-004` | Logging | Bulk inspect of likely payload variable (`bulk_inspect`) | `LOW` unless corroborated by stronger evidence | `Logger.debug(inspect(params))` |
| `PS-SCAN-005` | HTTP | Outbound HTTP call carries PRD-linked fields | `HIGH`/`MEDIUM`/`LOW` | `Req.post("https://vendor.example/api", json: %{email: user.email})` |
| `PS-SCAN-006` | Controller | Controller response path exposes PRD-linked fields | `HIGH`/`MEDIUM`/`LOW` | `json(conn, %{email: user.email, id: user.id})` |
| `PS-SCAN-007` | Telemetry | Telemetry/analytics emit includes PRD-linked fields | `HIGH`/`MEDIUM`/`LOW` | `:telemetry.execute([:acme,:login], %{}, %{email: user.email})` |
| `PS-SCAN-008` | Database | Repo read/write touches PRD-linked fields in call args | `HIGH`/`MEDIUM`/`LOW` | `Repo.insert(%AuditLog{user_id: user.id, email: user.email})` |
| `PS-SCAN-009` | LiveView | LiveView assign/push/render exposes PRD-linked fields | `HIGH`/`MEDIUM`/`LOW` | `push_event(socket, "profile", %{email: user.email})` |

Notes:

- Scan classification is `confirmed_prd` vs `possible_prd`.
- Scan markdown label mapping:
  - `HIGH`: confirmed + high sensitivity
  - `MEDIUM`: confirmed (non-high sensitivity)
  - `LOW`: possible

---

## Semantic Diff Registry (`PS-DIFF-*`)

| Registry ID | Semantic Change | Diff Rule IDs (from `PrivSignal.Diff.Severity`) | Typical Severity | Fictional Example |
|---|---|---|---|---|
| `PS-DIFF-001` | `flow_added` (external) | `R-HIGH-EXTERNAL-FLOW-ADDED` | High | New flow sends `student_email` to SaaS webhook |
| `PS-DIFF-002` | `flow_added` (internal) | `R-MEDIUM-INTERNAL-FLOW-ADDED` | Medium | New internal audit table write of `user_id` |
| `PS-DIFF-003` | `flow_removed` | `R-LOW-FLOW-REMOVED` | Low | Legacy export flow removed |
| `PS-DIFF-004` | `confidence_changed` | `R-LOW-CONFIDENCE-ONLY` | Low | Evidence confidence shifts without sink/boundary change |
| `PS-DIFF-005` | `flow_changed.external_sink_added` | `R-HIGH-EXTERNAL-SINK-ADDED` | High | Same logical flow now sends to third-party endpoint |
| `PS-DIFF-006` | `flow_changed.external_sink_changed` | `R-HIGH-EXTERNAL-SINK-CHANGED` | High | Vendor endpoint changed from `A` to `B` |
| `PS-DIFF-007` | `flow_changed.boundary_changed` to external | `R-HIGH-BOUNDARY-EXITS-SYSTEM` | High | Internal analytics path now exits system boundary |
| `PS-DIFF-008` | `flow_changed.boundary_changed` internalized | `R-LOW-BOUNDARY-INTERNALIZED` | Low | External path moved to internal sink |
| `PS-DIFF-009` | `flow_changed.behavioral_signal_persisted` | `R-MEDIUM-BEHAVIORAL-SIGNAL-PERSISTED` | Medium | Engagement metric newly persisted to storage |
| `PS-DIFF-010` | `flow_changed.inferred_attribute_external_transfer` | `R-HIGH-INFERRED-ATTRIBUTE-EXTERNAL-TRANSFER` | High | Risk score now transmitted to partner API |
| `PS-DIFF-011` | `flow_changed.sensitive_context_linkage_added` | `R-HIGH-SENSITIVE-CONTEXT-LINKAGE` | High | Pseudonymous ID newly linked with sensitive context |
| `PS-DIFF-012` | `flow_changed.sensitive_context_linkage_removed` | (currently falls to low default in diff severity) | Low | Sensitive context link removed from flow |
| `PS-DIFF-013` | `data_node_added.new_inferred_attribute` | `R-MEDIUM-NEW-INFERRED-ATTRIBUTE` | Medium | New inferred field `dropout_risk` introduced |
| `PS-DIFF-014` | Any unmatched change | `R-LOW-DEFAULT` | Low | Change not covered by a specific diff rule |

---

## Score Rubric Registry (`PS-SCORE-*`)

| Registry ID | Score Rule ID (from `PrivSignal.Score.RubricV2`) | Event Class | Detects | Fictional Example |
|---|---|---|---|---|
| `PS-SCORE-001` | `R2-HIGH-NEW-EXTERNAL-PII-EGRESS` | High | New external edge added | New external HTTP sink for `email` |
| `PS-SCORE-002` | `R2-HIGH-NEW-VENDOR-HIGH-SENSITIVITY` | High | Destination change with high sensitivity | Vendor switch for SSN-carrying flow |
| `PS-SCORE-003` | `R2-HIGH-EXTERNAL-HIGH-SENSITIVITY-EXPOSURE` | High | Boundary/sensitivity combo elevates exposure | Internal -> external with high-sensitive fields |
| `PS-SCORE-004` | `R2-HIGH-EXTERNAL-TRANSFORM-REMOVED` | High | External transform/link removal with removed list | External flow drops sensitive-context transform |
| `PS-SCORE-005` | `R2-MEDIUM-NEW-INTERNAL-SINK` | Medium | New internal edge added | New internal persistence sink for PRD data |
| `PS-SCORE-006` | `R2-MEDIUM-BOUNDARY-TIER-INCREASE` | Medium | Internal -> external boundary increase (non-high sensitivity path) | Externalization of medium-sensitivity path |
| `PS-SCORE-007` | `R2-MEDIUM-SENSITIVITY-INCREASE-ON-EXISTING-PATH` | Medium | Existing path sensitivity increased | Added medium-sensitive fields to existing route |
| `PS-SCORE-008` | `R2-MEDIUM-CONFIDENCE-AND-EXPOSURE-INCREASE` | Medium | Confidence and exposure both increase | Better evidence + added fields on same path |
| `PS-SCORE-009` | `R2-LOW-PRIVACY-RELEVANT-RESIDUAL-CHANGE` | Low | Residual low-severity changes | Non-escalating privacy-relevant delta |

Final score decision logic:

- `NONE` when `events_total == 0`
- `HIGH` when any high-class events exist
- `MEDIUM` when no high but any medium-class events exist
- `LOW` otherwise

---

## Traceability and Usage

- Use registry IDs in PR descriptions, test plans, and release notes to state expected detections.
- For staged validation suites, pair each synthetic PR with expected:
  - `PS-SCAN-*` entries (scan findings),
  - `PS-DIFF-*` entries (semantic changes),
  - `PS-SCORE-*` entries (score reasons/outcome).
