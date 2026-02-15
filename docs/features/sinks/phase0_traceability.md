# Phase 0 Traceability Matrix

References
- PRD: `docs/features/sinks/prd.md`
- FDD: `docs/features/sinks/fdd.md`
- Plan: `docs/features/sinks/plan.md`

## FR to Test Mapping

| FR ID | Contract Intent | Primary Tests | Status |
|---|---|---|---|
| FR-001 | Multi-category scanner contract exists; single-pass architecture planned | `test/priv_signal/scan/sinks_contract_test.exs` | Contract captured (pending impl) |
| FR-002 | HTTP sinks emit `role.kind=http` and boundary metadata | `test/priv_signal/scan/sinks_contract_test.exs`, `test/priv_signal/infer/sinks_adapter_contract_test.exs` | Contract captured (pending impl) |
| FR-003 | Controller response sinks emit `role.kind=http_response` | `test/priv_signal/scan/sinks_contract_test.exs`, `test/priv_signal/infer/sinks_adapter_contract_test.exs` | Contract captured (pending impl) |
| FR-004 | Telemetry sinks emit `role.kind=telemetry` | `test/priv_signal/scan/sinks_contract_test.exs`, `test/priv_signal/infer/sinks_adapter_contract_test.exs` | Contract captured (pending impl) |
| FR-005 | DB reads emit source; DB writes emit sink | `test/priv_signal/scan/sinks_contract_test.exs`, `test/priv_signal/infer/sinks_adapter_contract_test.exs` | Contract captured (pending impl) |
| FR-006 | LiveView exposure emits `role.kind=liveview_render` | `test/priv_signal/scan/sinks_contract_test.exs`, `test/priv_signal/infer/sinks_adapter_contract_test.exs` | Contract captured (pending impl) |
| FR-007 | `scanners` config schema and defaults | `test/priv_signal/config_schema_scanners_test.exs` | Contract captured (pending impl) |
| FR-008 | Stable node IDs with normalized context | `test/priv_signal/infer/sinks_adapter_contract_test.exs` | Contract captured (pending impl) |
| FR-009 | Proto-flow algorithm remains unchanged while accepting new kinds | `test/priv_signal/infer/sinks_adapter_contract_test.exs` | Contract captured (pending impl) |
| FR-010 | Category-level telemetry coverage | `test/priv_signal/scan/sinks_contract_test.exs` | Contract captured (pending impl) |
| FR-011 | Backward compatibility when `scanners` section omitted | `test/priv_signal/config_schema_scanners_test.exs` | Contract captured (pending impl) |

## Notes
- Phase 0 captures contracts and fixtures only.
- Contract assertions that depend on implementation are marked pending in tests and become active in Phase 1+.
