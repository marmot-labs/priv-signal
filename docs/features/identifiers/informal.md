What follows is an informal feature description. It should later be converted into a formal PRD.

# PrivSignal — Privacy-Relevant Data (PRD) Ontology Expansion (Informal)

## Context

PrivSignal has so far operated with a narrow framing centered on "PII detection." That framing is no longer sufficient for modern privacy analysis and understates the real privacy risk surface introduced by behavioral aggregation, persistent identifiers, and inferred attributes.

This feature introduces a broader ontology of privacy-relevant data so PrivSignal can detect meaningful privacy drift beyond conventional PII-only checks.

## Critical Compatibility Decision

Backward compatibility is explicitly **not required**.

This project has not been released. Therefore:

- No backward compatibility with prior YAML versions is needed.
- No backward compatibility with prior lockfile/output formats is needed.
- No migration guarantees are required for pre-existing config structure.
- We can make clean architectural changes now without compatibility constraints.

This decision is intentional and should guide schema and implementation choices throughout this work.

## Concept Rename (Internal + Product Framing)

Stop framing this as "PII detection" and reframe as:

**Privacy-Relevant Data (PRD) Detection**

PII remains supported, but as one subtype inside a broader model.

## v1 Ontology (Minimal and Implementable)

Use exactly five core classes in v1:

1. **direct_identifier**
Data that uniquely identifies a person.
Examples: `name`, `email`, `ssn`, `phone`, `biometric_template`

2. **persistent_pseudonymous_identifier**
Not directly identifying in isolation, but stable over time and linkable.
Examples: `user_id`, `device_id`, long-lived `session_token`, `account_id`, `hashed_email`

3. **behavioral_signal**
Events or activity traces that capture user behavior.
Examples: `page_view`, `click_event`, `search_query`, `time_spent`, `purchase_event`, `location_history`

4. **inferred_attribute**
Computed/model-derived attributes inferred from other data.
Examples: `risk_score`, `engagement_score`, `churn_probability`, `mental_health_flag`, `political_affinity_score`, `classification_label`

5. **sensitive_context_indicator**
Signals tied to high-risk or protected contexts.
Examples: `health_category`, `religious_tag`, `financial_distress`, `disability_marker`, `student_accommodation_flag`

This ontology must stay compact in v1: five classes only.

## Practical Detection Strategy

Perfect semantic inference is out of scope. Detection should be structural and evidence-based.

### A) Static heuristics

Use naming and context cues such as:

- Suffix/pattern hints: `_id`, `_token`, `_score`, `_prediction`, `_classification`, `_flag`, `_category`
- Module/domain hints: `RiskEngine`, `MLModel`, `Analytics`, `Tracking`, `Engagement`
- Type hints: floating-point computed metrics often indicate `inferred_attribute`
- Type hints: boolean fields ending in `_flag` may indicate `inferred_attribute` or `sensitive_context_indicator`

### B) Agent-assisted classification

Generalize the current PII inference agent into a:

**Privacy-Relevant Data Classification Agent**

Inputs:

- Field/identifier name
- Local code context
- Module/service purpose
- Inline comments/docstrings

Output example:

```json
{
  "name": "engagement_score",
  "data_class": "inferred_attribute",
  "confidence": 0.82,
  "rationale": "Derived metric computed from user activity signals."
}
```

## Lockfile / Artifact Model Upgrade

Upgrade output to support richer nodes and flows, for example:

```json
{
  "data_nodes": [
    {
      "name": "email",
      "class": "direct_identifier",
      "sensitive": false
    },
    {
      "name": "engagement_score",
      "class": "inferred_attribute",
      "sensitive": false
    }
  ],
  "flows": [
    {
      "from": "engagement_score",
      "to": "analytics_service",
      "boundary": "external"
    }
  ]
}
```

## Trigger Types Enabled by This Ontology

Moving to PRD enables materially stronger structural triggers:

1. New inferred attribute introduced
Example: `+ engagement_score (inferred_attribute)`
Interpretation: new profiling surface

2. Behavioral signal becomes persisted
Example: `+ search_query -> db`
Interpretation: narrative-building potential increases

3. Inferred attribute sent externally
Example: `+ risk_score -> analytics_service`
Interpretation: profiling export

4. Persistent identifier linked to sensitive/new class
Example: `+ user_id -> mental_health_category`
Interpretation: identifiability and harm potential escalate

## Scope Discipline

Keep v1 narrow and structural.

In scope:

- Detect introduction/propagation of PRD classes in code and config artifacts
- Classify identifiers/signals into the five-class ontology
- Diff structural changes and trigger reassessment signals

Out of scope:

- Modeling complete narrative construction over time
- Quantifying psychological or societal harm
- Solving full implicit inference discovery
- Heavy semantic/causal inference beyond available static evidence

## Research and Evaluation Framing

This shift supports a stronger thesis and evaluation model:

- Prior tools focus narrowly on PII.
- Modern privacy harms often arise from behavior + inference + linkage.
- PrivSignal detects privacy-relevant drift using a compact ontology that includes both identifying and implicative data.

Evaluation can compare:

- Detection precision by class (`direct_identifier` vs `inferred_attribute`, etc.)
- False positives in behavioral/inferred classes
- Risk signal quality: PII-only baseline vs PRD ontology baseline

## Strategic Outcome

This change aligns PrivSignal with modern privacy engineering and governance trends while keeping implementation scope tractable.

It is an architectural upgrade, not a speculative expansion.
