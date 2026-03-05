  1. Improve PRD matching from literal to “normalized + controlled fuzzy”

  - Current hotspots: evidence.ex, inventory.ex
  - Recommendation:
      - Add token normalization pipeline: singularization (emails -> email),
        separator/case splitting (userEmail, user_email), optional prefix stripping
        (submitted_email -> email).
      - Add config-driven alias/synonym map in priv_signal.yml (explicit,
        reviewable, low risk).
      - Keep fuzzy matching gated by confidence tier (exact, normalized, alias) so
        output remains explainable.
  - Why: solves most “submitted_emails/invitee_emails” misses without uncontrolled
    false positives.

  2. Add wrapper-aware DB sink detection

  - Current hotspot: database.ex
  - Recommendation:
      - Introduce scanners.database.wrapper_modules + wrapper_functions config.
      - Build lightweight function summaries: mark local functions as db_write/
        db_read if they contain Repo.*; when those functions are called, emit
        inherited sink classification.
      - Start intra-module only; avoid full project call graph initially.
  - Why: catches Persistence.append_step(...)-style patterns while preserving
    deterministic behavior.

  3. Add payload provenance for HTTP scanner

  - Current hotspot: http.ex
  - Recommendation:
      - Add intra-function dataflow/provenance pass:
          - Track variable assignments from PRD-linked fields.
          - Propagate through common builders (Map.put, Map.merge, keyword/map
            literals, Jason.encode!).
          - At sink call, resolve argument variables to provenance graph.
      - Emit evidence type like :indirect_payload_ref with source variable chain
        for explainability.
  - Why: fixes misses where sink args are prebuilt/encoded.

  4. Introduce a staged confidence model instead of binary miss/hit

  - Apply across all 3 improvements:
      - confirmed (direct AST evidence)
      - probable (normalized/alias/provenance)
      - possible (weak heuristics)
  - Keeps precision for CI decisions while increasing recall.

  5. Implementation order (recommended)
  6. Config aliases + token normalization (fastest ROI, lowest risk)
  7. DB wrapper config + intra-module summaries
  8. HTTP provenance (highest impact, more complexity)
  9. Confidence model harmonization + docs update in classification_registry.md
  10. Validation strategy before rollout

  - Add fixture-based regression suites for each limitation:
      - pluralized/derived token names
      - DB wrapper indirection
      - HTTP prebuilt/encoded payloads
  - Track precision drift with “strict exact-only mode” toggle for comparison
    during rollout.