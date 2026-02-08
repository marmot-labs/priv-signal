Informal PRD — Phase 3: Artifact Diff Engine

(Semantic diffs, not JSON noise)

Goal

Make privacy-related PR feedback crisp, actionable, and reviewable by humans.

Instead of saying “priv-signal.yml changed” or dumping raw JSON diffs, this phase introduces a semantic diff engine that explains what actually changed in privacy terms between two versions of the privacy artifacts.

The outcome should be that a reviewer can read the output and immediately understand:

What privacy flows changed?

Why does it matter?

How severe is it?

Problem Statement

PrivSignal already produces structured artifacts:

YAML data-flow specifications

JSON results from scanners (logging, PII inventory, etc.)

However, standard diffs:

are noisy (ordering changes, formatting, metadata)

do not reflect privacy semantics

force reviewers to manually infer risk

For CI and PR review, this leads to poor UX:

“Something changed, but I don’t know what or whether I should care.”

This phase fixes that by diffing meaning, not structure.

Scope (Phase 3)

This phase introduces a new command:

mix priv_signal.diff --base <ref> --candidate <ref>


It compares two snapshots of privacy artifacts (typically from two git refs) and emits a semantic privacy diff.

This phase focuses on data flows and PII-related artifacts, not arbitrary config.

Inputs

Base artifacts (from --base ref):

Parsed data-flow YAML

Parsed PII declarations

Optional scanner outputs (logging inventory, etc.)

Candidate artifacts (from --candidate ref):

Same structures, post-change

The diff engine operates on normalized, parsed representations, not raw files.

Semantic Diff Categories

The diff engine classifies changes into privacy-meaningful categories, not line-level edits.

1. Added / Removed Flows

Detect when a data flow is:

newly introduced

removed entirely

Examples:

“New flow added: export_roster_csv (PII exits system)”

“Flow removed: legacy_enrollment_sync”

These are high-signal changes and should always be surfaced.

2. Flow Changed

Detect changes to an existing flow’s privacy semantics, including:

a) Sinks Changed

Internal → external

External recipient added/removed

Logging / export added

Example:

“Flow user_registration: new external sink Mailgun added”

b) Fields Expanded or Reduced

New PII fields added to a flow

Sensitivity increased/decreased

Example:

“Flow user_registration: PII fields expanded (added dob, high sensitivity)”

c) Boundary Changed

Flow now exits the system

Flow previously internal now crosses a trust boundary

Example:

“Flow analytics_event: boundary changed (now exits system)”

3. Confidence Changed (Optional / Low Priority)

Track changes in confidence levels for findings (e.g., from inventory/scanners):

“possible” → “confirmed”

“confirmed” → “possible”

This is useful but not critical for v1 and can be deprioritized.

Severity Scoring (Simple, Deterministic)

The diff engine assigns a coarse severity to each semantic change to guide reviewer attention.

Initial rules (intentionally simple):

High

External sink added

Logging of high-sensitivity PII introduced

Boundary change causing data to exit the system

Medium

New internal data flow

Expansion of PII fields (medium sensitivity)

New observability surface (logs/telemetry) with PII

Low

Flow removal

Internal refactoring with no boundary or PII change

Confidence changes only

Severity is advisory, not enforcement.

Output Formats
1. Human-Readable Summary (Default)

Optimized for PR comments and developer review.

Example:

Privacy-Relevant Changes Detected

HIGH:
- New external disclosure added:
  Flow: export_roster_csv
  Sink: S3 Exports Bucket
  Fields: email, student_id

MEDIUM:
- Flow user_registration expanded:
  Added field: phone (contact, medium sensitivity)

LOW:
- Internal flow cleanup:
  Removed legacy_enrollment_sync


This should be readable in under 30 seconds.

2. JSON Output (For CI / Automation)

Structured output suitable for:

GitHub Checks annotations

CI dashboards

Future policy engines

Example (conceptual):

{
  "summary": {
    "high": 1,
    "medium": 1,
    "low": 1
  },
  "changes": [
    {
      "type": "flow_changed",
      "flow_id": "export_roster_csv",
      "change": "external_sink_added",
      "severity": "high",
      "details": { ... }
    }
  ]
}

Exit Criteria

This phase is complete when:

CI can say what changed in privacy terms, not just that files differ.

Reviewers can understand privacy impact without reading raw YAML or JSON.

The diff engine reliably ignores:

ordering changes

formatting noise

irrelevant metadata

The output clearly distinguishes:

new risk

changed risk

removed risk

Success is not perfect accuracy — success is reviewer clarity.

Explicit Non-Goals (For This Phase)

Blocking PRs based on severity

Full policy enforcement

Deep probabilistic scoring

Reconstructing full end-to-end data flows

Those may come later, but this phase is about explainability and signal quality.