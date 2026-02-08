# Enhanced Scan Phase 0 Traceability Matrix

References
- PRD: `docs/features/enhanced_scan/prd.md`
- FDD: `docs/features/enhanced_scan/fdd.md`
- Plan: `docs/features/enhanced_scan/plan.md`

## FR to AC Mapping
- FR-001 -> AC-001
- FR-002 -> AC-002
- FR-003 -> AC-003
- FR-004 -> AC-004
- FR-005 -> AC-005
- FR-006 -> AC-003
- FR-007 -> AC-002
- FR-008 -> AC-006
- FR-009 -> AC-007
- FR-010 -> AC-002
- FR-011 -> AC-001
- FR-012 -> AC-009
- FR-013 -> AC-008
- FR-014 -> AC-006

## Phase 0 Contract Coverage
- Contract schema keys and node required fields:
  - `test/priv_signal/infer/contract_test.exs`
- Inference-agnostic artifact contract (no edges):
  - `test/priv_signal/infer/contract_test.exs`
- Deterministic identity excluding non-semantic fields:
  - `test/priv_signal/infer/contract_test.exs`
  - `test/priv_signal/infer/determinism_property_test.exs`
- Deterministic sorting guarantees:
  - `test/priv_signal/infer/contract_test.exs`
  - `test/priv_signal/infer/determinism_property_test.exs`

## Assumptions Captured in Phase 0
- Identity excludes evidence line numbers, timestamps, and runtime metadata.
- Canonical tuple includes `node_type`, module, function, normalized path, role kind, and PII references.
- Standalone `entrypoint` node emission remains a later-phase decision.
