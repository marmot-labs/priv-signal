# Phase 0 FR-to-Test Traceability Matrix

References
- PRD: `docs/features/scan/prd.md`
- FDD: `docs/features/scan/fdd.md`
- Plan: `docs/features/scan/plan.md`

| FR ID | Requirement Summary | Contract Test Coverage | Status |
| --- | --- | --- | --- |
| `SCN-FR-01` | `pii` declarations are authoritative | `test/priv_signal/config_schema_test.exs`, `test/priv_signal/scan_phase0_contract_test.exs` | Complete (Phase 5) |
| `SCN-FR-02` | Deterministic inventory from config | `test/priv_signal/scan/inventory_test.exs`, `test/priv_signal/scan/determinism_test.exs` | Complete (Phase 5) |
| `SCN-FR-03` | AST logging sink scanning | `test/priv_signal/scan/logger_test.exs` | Complete (Phase 5) |
| `SCN-FR-04` | Evidence and location context | `test/priv_signal/scan/logger_test.exs`, `test/priv_signal/scan/output_json_test.exs` | Complete (Phase 5) |
| `SCN-FR-05` | Confirmed vs possible classification | `test/priv_signal/scan/classifier_test.exs` | Complete (Phase 5) |
| `SCN-FR-06` | JSON + Markdown reporting | `test/priv_signal/scan/output_json_test.exs`, `test/priv_signal/scan/output_markdown_test.exs`, `test/priv_signal/scan_phase0_contract_test.exs` | Complete (Phase 5) |
| `SCN-FR-07` | Hard cutover to `pii` source | `test/priv_signal/config_schema_test.exs`, `test/mix/tasks/priv_signal_validate_test.exs`, `test/mix/tasks/priv_signal_score_test.exs`, `test/mix/tasks/priv_signal_scan_test.exs` | Complete (Phase 5) |
| `SCN-FR-08` | Existing workflows operate via normalized `pii` | `test/priv_signal/validate_test.exs`, `test/mix/tasks/priv_signal_score_test.exs` | Complete (Phase 5) |
| `SCN-FR-09` | Distinguish config errors from findings | `test/mix/tasks/priv_signal_scan_test.exs`, `test/priv_signal/scan/resilience_test.exs` | Complete (Phase 5) |

Notes
- This file mirrors the final FR evidence section in `docs/features/scan/plan.md`.
