What follows is an informal feature description: It needs to be converted and updated into a formal PRD according to given constraints.  Save the formal one to docs/features/enhanced_scan/prd.md

PrivSignal — PII Scanning Expansion (Proto-Flow–Ready Inventory)
Background / Context

PrivSignal currently includes a PII scanning feature that statically analyzes Elixir code and detects instances where PII is used in logging calls. This initial implementation has proven the viability of AST-based PII detection and has surfaced useful, concrete findings (e.g., logging of email, phone, etc.).

However, the current scanner is narrowly scoped (logging only) and produces output that is tightly coupled to the specific check rather than serving as a reusable, structured representation of where and how PII appears in the system.

As PrivSignal evolves toward automatic inference of Proto Flows (privacy-relevant data flows), the PII scanning subsystem must evolve into a general-purpose PII inventory generator that produces stable, deterministic “nodes” representing PII touchpoints across the codebase.

This PRD focuses exclusively on expanding and restructuring PII scanning to support that goal. Proto flow inference itself is explicitly out of scope for this work.

Problem Statement

PrivSignal needs a reliable, deterministic way to answer:

“Where does PII appear in this codebase, in what context, and in what role?”

The current logging-only scanner:

Does not capture enough contextual metadata to support downstream flow inference

Produces findings that are not normalized or structured as reusable graph nodes

Does not generalize to other privacy-relevant contexts (controllers, HTTP, DB, telemetry, etc.)

Without a richer and more uniform inventory layer, any inferred flow system would either:

Be brittle and incomplete, or

Require re-analyzing raw AST findings repeatedly

Goals

Expand PII scanning beyond logging
While logging remains the first and most mature scanner, the system should be designed to support additional PII touchpoints incrementally (controllers, LiveViews, HTTP clients, DB access, telemetry, files, etc.).

Capture sufficient context for each PII occurrence
Every detected PII usage must include enough structural context to:

Understand where it occurs (module, function, file)

Understand what role it plays (source, sink, entrypoint, transform)

Serve as a stable anchor for inferred Proto Flows

Produce a deterministic, structured node inventory
Scanner output should be emitted as a normalized JSON structure consisting of nodes, not ad-hoc findings. This structure must be stable across runs and suitable for use as a lockfile artifact.

Remain inference-agnostic
This phase should not attempt to infer relationships between nodes. Its sole responsibility is to surface high-quality, well-classified nodes with evidence.

Non-Goals

Inferring data flows or relationships between nodes

Performing interprocedural or “heavy” taint analysis

Enforcing privacy policy or failing builds

Generating human-readable explanations or PR comments

Conceptual Model

The output of PII scanning will be a node inventory. Each node represents a single, concrete PII-relevant touchpoint in the code.

Nodes fall into several high-level types (some may be unimplemented initially, but must be represented structurally):

entrypoint

Controllers, LiveViews, jobs, background workers

Places where data enters or is handled at system boundaries

source

Database fields

Request parameters

External inputs

sink

Logging

HTTP clients / external services

Telemetry / analytics

File writes

transform

Redaction

Hashing

Filtering

Serialization

Each node is independent; no edges or flows are created at this stage.

Required Context Captured Per Node

Each PII node must include enough information to be independently meaningful and composable later.

At minimum, nodes should capture:

Node identity

Stable, deterministic ID (derived from normalized attributes)

Node type (entrypoint / source / sink / transform)

PII metadata

PII field or reference (e.g., User.email)

Category (contact, identifier, special, etc.)

Sensitivity (low / medium / high)

Code context

Module name

Function name and arity (if applicable)

File path (normalized, repo-relative)

Line number(s) (as evidence, not identity)

Structural role

For sinks: what kind (logger, http, telemetry, file)

For entrypoints: controller, liveview, job, etc.

For transforms: transformation type (if detectable)

Evidence

AST-derived references supporting the classification

Used for explainability and confidence scoring later

Where classification is heuristic (e.g., module type), the node should include:

A confidence score

A list of evidence signals (e.g., use MyAppWeb, :controller, file path pattern)

Determinism Requirements

The node inventory must be fully deterministic:

Same codebase → same node set → same JSON output

Independent of machine, OS, or run order

Specifically:

File paths must be normalized

Module and function names must be canonical

Nodes must be sorted consistently

Node IDs must be derived from semantic identity, not line numbers

Line numbers and AST metadata are treated as evidence, not part of node identity.

Phased Scanner Expansion

This PRD covers restructuring the scanner so it can support expansion, even if not all scanners are implemented immediately.

Initial implementation priorities:

Logging scanner (existing) → refactored to emit nodes

Module classification (controller, liveview, etc.) as entrypoint context

Structural scaffolding for additional node types

Future scanners (explicitly out of scope here but supported by design):

HTTP client calls

Controller responses

LiveView assigns/rendering

Database reads/writes

Telemetry/analytics events

Developer Experience

Running mix priv_signal.scan produces a node inventory as part of the generated artifact.

Developers do not manually edit node definitions.

Node output is reviewable but treated as generated data.

Manual assertions or overrides (if needed) will be handled separately, not by editing generated nodes.

Success Criteria / Exit Criteria

This phase is complete when:

PII scanning produces a deterministic JSON node inventory

Logging-based PII findings are fully represented as structured nodes with context

Node output is stable across runs and suitable for check-in as a lockfile artifact

The inventory can serve as a reliable backbone for a future Proto Flow inference step without redesign
