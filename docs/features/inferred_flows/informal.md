PrivSignal — Proto Flow Inference v1 (Single-Scope, Rules-Based)
Overview

Feature Name
Proto Flow Inference v1 (Single-Scope, Same-Unit)

Summary
PrivSignal will introduce a first-generation Proto Flow inference step that builds on the Phase 1 PII node inventory (enhanced-scan). This phase infers coarse-grained, privacy-relevant data flows within a single, well-defined unit of work (e.g., a function, controller action, or LiveView event handler) using deterministic, rules-based heuristics. The goal is to surface useful and stable flow candidates without interprocedural analysis, heavy taint tracking, or LLM involvement.

The resulting Proto Flows are intended to be loss-tolerant, explainable, and suitable for diff-based review. This phase deliberately avoids whole-program reasoning and focuses on correctness, determinism, and developer trust.

Background & Motivation

Phase 1 established a deterministic PII inventory that emits normalized nodes representing PII touchpoints (sources, sinks, entrypoints, transforms) with stable identity and evidence.

Phase 2 builds directly on that inventory by answering a higher-level question:

“Within a single unit of work, do we see PII being handled and then exposed, stored, or emitted?”

Rather than attempting precise end-to-end reachability, this phase introduces Proto Flows as a pragmatic abstraction: a likely flow of PII from a source (or inferred source) to a sink, anchored to an entrypoint, with confidence and evidence.

This step is critical for:

Making inventory information actionable

Enabling future diff-based privacy risk detection

Avoiding the complexity and brittleness of heavy taint analysis

Goals

Infer Proto Flows using only information available within a single scope (module/function/event).

Keep inference deterministic and rules-based (no LLM usage).

Produce stable flow objects that can be serialized alongside nodes in privsignal.json.

Ensure flows are explainable via node-level evidence.

Keep false positives acceptable but bounded; prefer recall over precision at this stage.

Non-Goals

Interprocedural dataflow or whole-program taint analysis.

Precise variable-level or path-sensitive tracking.

Inferring multi-hop or cross-module flows.

Policy enforcement or CI gating based on flows.

Human-authored flow definitions (manual assertions handled separately).

LLM-based inference or summarization.

Conceptual Model

A Proto Flow is a coarse, privacy-semantic summary of data movement, not an execution trace.

Each Proto Flow captures:

source
The PII field or reference involved (e.g., User.email).
In v1, this may be:

directly observed from PII nodes, or

inferred as “PII touched” within the unit.

entrypoint
The logical boundary of the unit of work:

controller action (create/2)

LiveView event (handle_event/3)

job handler, etc.

sink
The PII sink involved (logger, HTTP client, telemetry, etc.).

boundary
A coarse trust boundary classification:

internal

external
(v1 defaults to internal unless clearly external)

confidence
A heuristic score representing inference strength.

evidence
References to the underlying node IDs that justify the flow.

Proto Flows intentionally omit:

intermediate transforms

call chains

control-flow details

Inference Strategy (v1)
Unit of Work Definition

Proto Flow inference operates within a single unit of work, defined as:

a function body (including anonymous functions nested within it), or

a recognized entrypoint handler (controller action, LiveView callback).

No inference crosses:

function boundaries

modules

files

Core Heuristic (Anchor Rule)

Within a single unit of work:

If PII is touched AND a PII sink is present, infer a candidate Proto Flow.

More concretely:

One or more PII-related nodes (source or transform) are present in the unit.

One or more sink nodes (e.g., logger) are present in the same unit.

These nodes share a common code context (module + function).

This produces a Proto Flow candidate.

Confidence Heuristics (Initial)

Confidence scoring is heuristic and additive. Examples:

+0.5 if PII node and sink node share exact function context

+0.2 if sink directly references PII field

−0.2 if PII classification is “possible” rather than “confirmed”

−0.2 if inference relies on indirect evidence only

Scores are clamped to [0.0, 1.0].

The exact weights are tunable but must be deterministic.

Output Model

Proto Flows are serialized alongside nodes in the same artifact.

Example (illustrative):

{
  "flows": [
    {
      "id": "psf_9c31a7e2b0ad",
      "source": "Oli.Accounts.User.email",
      "entrypoint": "MyAppWeb.UserController.create/2",
      "sink": {
        "kind": "logger",
        "subtype": "Logger.info"
      },
      "boundary": "internal",
      "confidence": 0.82,
      "evidence": [
        "psn_014939e3417679ea",
        "psn_6f2bb5a9df3e"
      ]
    }
  ]
}


Key properties:

Flow IDs are deterministic and derived from semantic identity (not node IDs directly).

Evidence references node IDs, not raw AST or scan findings.

Ordering is canonical and stable.

Determinism Requirements

Same input code + same node inventory ⇒ identical flow output.

No timestamps, randomness, or environment-specific data.

Flow IDs and ordering must be stable across runs.

Changes in evidence ordering or confidence rounding must not cause unnecessary churn.

Developer Experience

Proto Flows are generated automatically as part of mix priv_signal.infer.

Developers do not manually edit inferred flows.

Flow output is reviewable in PR diffs but treated as machine-generated.

No new CLI surface is required in this phase.

Success / Exit Criteria

This phase is complete when:

privsignal.json includes a non-empty flows section for real-world codebases.

Flow output is stable across repeated runs on unchanged code.

Flows reliably reflect obvious cases (e.g., logging of PII in controllers/LiveViews).

Flow inference does not introduce significant performance regressions.

Downstream tooling can consume flows without re-examining AST or scan artifacts.

Risks & Mitigations

Risk: False positives in simple heuristics
Mitigation: Confidence scoring + evidence transparency; no enforcement.

Risk: Over-eager inference within complex functions
Mitigation: Keep scope local; prefer under-inference to aggressive chaining.

Risk: Developer mistrust of inferred flows
Mitigation: Determinism, stable IDs, and explicit evidence references.

Explicitly Deferred

Cross-function and cross-module flow inference

Transform chaining and redaction modeling

Policy evaluation and CI blocking

Manual flow assertions and overrides

LLM-assisted inference or summarization