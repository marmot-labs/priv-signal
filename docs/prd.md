PrivSignal – Product Requirements Document (PRD)
1. Overview

PrivSignal is an open-source Elixir command-line tool that generates a privacy risk category for GitHub pull requests by analyzing code changes against a project-defined map of privacy-relevant data flows.

PrivSignal is designed to operationalize Privacy Impact Assessment (PIA) principles directly within the software development lifecycle by providing developers and reviewers with a clear, explainable privacy risk signal at PR time, without blocking builds or asserting compliance.

PrivSignal is intentionally advisory, not enforcement-oriented.

2. Problem Statement

Privacy Impact Assessments are typically:

manual and document-centric,

conducted infrequently,

and disconnected from everyday development practices.

As a result:

privacy risk accumulates incrementally through normal code changes,

engineers lack timely feedback when modifying privacy-sensitive logic,

and PIAs quickly become outdated relative to the codebase.

The Elixir/Phoenix ecosystem currently lacks tooling that:

is privacy-specific,

understands application-specific data flows,

and surfaces privacy risk at the point of code review.

3. Goals and Non-Goals
3.1 Goals

PrivSignal aims to:

Generate a single privacy risk category for each pull request:

None, Low, Medium, or High

Detect when PRs:

touch known privacy-relevant data flows

introduce new personal data usage

introduce new data sinks or external transfers

Provide clear, evidence-based explanations for the assigned risk category

Integrate naturally into Elixir developer workflows:

local execution via Mix task

CI/CD execution (e.g., GitHub Actions)

Be driven entirely by explicit, human-authored configuration (YAML)

Remain open source, framework-agnostic, and reusable across Elixir projects

3.2 Non-Goals

PrivSignal explicitly does not aim to:

block merges or fail CI builds

claim regulatory compliance

perform full static taint analysis

automatically infer all data flows

generate full DPIA documentation

PrivSignal is a risk signaling and decision-support tool, not a compliance engine.

4. Target Users

Elixir / Phoenix developers

Tech leads reviewing pull requests

Privacy-aware engineering teams

Open-source maintainers

The primary user is a developer or reviewer evaluating a PR.

5. Conceptual Model

PrivSignal operates on three core ideas:

Explicit system knowledge
Privacy-relevant data flows are declared manually in a YAML file and treated as authoritative.

Change-based analysis
Only the code changes introduced by a PR are analyzed.

Categorical risk signaling
Output is a simple, interpretable risk label—not a pass/fail judgment.

6. Configuration: priv-signal.yml
6.1 Purpose

priv-signal.yml defines a living inventory of critical personal data flows and known PII-bearing components in the system.

It is authored and maintained by the development team and reviewed as part of normal code changes.

6.2 Example Structure
version: 1

```
pii_modules:
  - MyApp.Accounts.User
  - MyApp.Accounts.Author

flows:
  - id: xapi_export
    description: "User activity exported as xAPI statements"
    purpose: analytics
    pii_categories:
      - user_id
      - ip_address
    path:
      - module: MyAppWeb.ActivityController
        function: submit
      - module: MyApp.Analytics.XAPI
        function: build_statement
      - module: MyApp.Storage.S3
        function: put_object
    exits_system: true
    third_party: "AWS S3"
```



6.3 Semantics

Flows reference real Elixir modules and functions

exits_system and third_party flags directly influence risk categorization

The YAML file is the source of truth for what is considered a known, reviewed flow

7. Analysis Model
7.1 Inputs

PrivSignal analyzes:

Git diff between base and head commits

priv-signal.yml

Optional repo-level glossary (future)

Only changed files and hunks are considered.

7.2 LLM-Based Diff Analysis

PrivSignal uses a Large Language Model (LLM) to analyze PR diffs with the following constraints:

PrivSignal supports OpenAI API compatible models. Environment variables allow overriding the model URL and supplying model API keys.

The model is provided:

the unified diff

a structured summary of defined flows and PII modules

The model is instructed to:

reason only about added or modified lines

cite concrete evidence (file + line range)

report uncertainty explicitly

The model outputs structured JSON, not prose

The LLM is used for:

identifying whether defined flows are touched

detecting new PII usage or sinks outside defined flows

classifying privacy-relevant changes

The LLM does not assign risk labels.

7.3 Deterministic Interpretation Layer

PrivSignal validates and interprets LLM output locally:

schema validation

evidence checks

confidence weighting

normalization into internal risk events

This ensures:

repeatable behavior

explainability

separation of inference from policy

8. Privacy Risk Categories

PrivSignal outputs one category per PR.

8.1 None

Definition:
No privacy-relevant impact detected.

Signals:

No defined flows touched

No new PII categories

No new sinks or exports

8.2 Low

Definition:
Changes are confined to existing, known privacy boundaries.

Signals:

Touches existing YAML-defined flows

No new PII categories

No new data leaving the system

8.3 Medium

Definition:
PR expands or alters personal data processing within the system boundary.

Signals:

New PII categories introduced internally

New internal persistence or export (CSV, jobs)

Existing flows expanded to include more data

8.4 High

Definition:
PR introduces new external exposure or high-sensitivity risk.

Signals:

New third-party transfer

New PII usage outside defined flows

Sensitive data categories

New bulk exports or logging of PII

9. Outputs
9.1 Human-Readable

Markdown summary suitable for PR comments

Assigned risk category

Bullet list of contributing factors

Evidence excerpts

9.2 Machine-Readable

JSON artifact for CI systems

Structured risk events

Exit code always 0 (informational only)

10. CLI and Mix Tasks
10.1 Installation

PrivSignal is installed as a Mix dependency or archive.

10.2 Commands
mix priv_signal.init
mix priv_signal.score
mix priv_signal.score --base origin/main --head HEAD

10.3 GitHub Actions

PrivSignal is designed to be invoked by a GitHub Action that:

checks out the repo

runs mix priv_signal.score

posts the summary as a PR comment

11. Success Criteria

PrivSignal is successful if:

Developers understand why a PR received a given risk label

Risk categories are stable and predictable

False positives are explainable and correctable via YAML

Teams can adopt PrivSignal with minimal configuration

The tool demonstrates a concrete, operational privacy control

12. Future Enhancements (Out of Scope)

Code annotations

AST-based static analysis

CI enforcement modes

Automatic data flow diagram generation

DPIA document export

Local-only (non-LLM) analysis mode

13. Academic Framing

PrivSignal demonstrates:

privacy-by-design principles

proportional risk-based assessment

integration of privacy into SDLC

human-in-the-loop decision support

policy-as-code concepts applied to privacy
