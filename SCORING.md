# PrivSignal Scoring

PrivSignal assigns one of four privacy scores to a code change: `NONE`, `LOW`, `MEDIUM`, or `HIGH`.

The goal is simple: highlight changes that may affect how personal data is handled, exposed, stored, or transferred so reviewers know when a closer privacy review is needed.

This document explains the scoring model in plain language. It is intentionally product-level guidance, not an explanation of internal implementation details.

## Core Terms

### Source

A source is where privacy-relevant data comes from or is read from.

Examples:

- Reading `email` or `user_id` from a user record
- Loading profile attributes from a database
- Accessing account data inside a controller or service
- Pulling behavioral or inferred attributes into application logic

### Sink

A sink is where privacy-relevant data goes.

Examples:

- Writing data to logs
- Sending data to telemetry or analytics
- Returning data in an API response
- Assigning data into a UI or LiveView
- Sending data to an external HTTP service
- Writing data to a database or other persistent store

In short:

- Sources are where data is obtained
- Sinks are where data is exposed, stored, or sent

## What PrivSignal Detects

PrivSignal detects privacy-relevant changes in how known data moves through the system.

Typical examples include:

- New logging of personal data
- New telemetry or analytics export
- New API or UI exposure of personal data
- New outbound transfer to an external service
- New persistence of behavioral, inferred, or sensitive attributes
- Changes in destination, boundary, or exposure level
- Removal of a protective transformation before exposure or transfer

PrivSignal is not trying to decide whether a change is legally acceptable. It is surfacing changes that are likely to matter from a privacy review perspective.

## How To Read The Score

The score reflects the most privacy-significant change in the diff.

- `NONE` means no privacy-relevant change was detected
- `LOW` means something privacy-related changed, but it does not appear to expand exposure in a meaningful way
- `MEDIUM` means the change expands handling or exposure in a way that deserves review
- `HIGH` means the change introduces a clearly material privacy risk or expands exposure across a meaningful boundary

## `NONE`

`NONE` means the change does not alter privacy-relevant data handling in a meaningful way.

Typical cases:

- Refactoring code without changing what data is read, exposed, stored, or transferred
- Renaming functions or modules
- Changing formatting, comments, or tests only
- Editing code near privacy-related logic without changing the actual data flow

Example:

```elixir
# Before
Logger.info("job started")

# After
Logger.info("job started for nightly sync")
```

Why this is `NONE`:

- No privacy-relevant data was newly introduced
- No new source or sink was added for personal data

## `LOW`

`LOW` means a privacy-relevant area changed, but the change does not clearly increase exposure or risk on its own.

Typical cases:

- Reworking an existing privacy-related flow without expanding who receives the data
- Removing a sink or reducing exposure
- Changing internal handling in a way that remains within the same trust boundary
- Making a small privacy-relevant change that should be visible to reviewers, but is not substantial

Example:

```elixir
# Before
Logger.info("user updated", email: user.email)

# After
# logging removed
```

Why this is `LOW`:

- The change is privacy-relevant
- Exposure was reduced rather than expanded
- Reviewers may still want to understand the behavioral change

Another example:

```elixir
# Before
Repo.insert!(%AuditEvent{user_id: user.id, action: "login"})

# After
Repo.insert!(%AuditEvent{user_id: user.id, action: "signed_in"})
```

Why this is `LOW`:

- The flow remains privacy-relevant
- The change does not materially expand the kind of data exposed or where it goes

## `MEDIUM`

`MEDIUM` means the change expands privacy-relevant handling or exposure enough that it should be deliberately reviewed.

Typical cases:

- Adding a new internal sink for personal data
- Persisting a new behavioral or inferred attribute
- Expanding a response, UI, or internal analytics event to include additional personal data
- Moving data into a broader internal audience or a more exposed context

Example:

```elixir
# Before
:telemetry.execute([:user, :login], %{}, %{user_id: user.id})

# After
:telemetry.execute([:user, :login], %{}, %{
  user_id: user.id,
  email: user.email
})
```

Why this is `MEDIUM`:

- A new sink now carries more personal data
- The exposure expanded, even if it remains inside internal systems

Another example:

```elixir
# Before
Repo.insert!(%UserProfile{user_id: user.id})

# After
Repo.insert!(%UserProfile{
  user_id: user.id,
  engagement_score: engagement_score
})
```

Why this is `MEDIUM`:

- The system now persists an additional behavioral or inferred attribute
- This is more privacy-significant than a refactor or reduction-only change

## `HIGH`

`HIGH` means the change introduces a material privacy exposure or crosses a meaningful boundary in a new or more risky way.

Typical cases:

- Sending personal data to a new external service
- Exposing sensitive data in an API or UI
- Broadening an existing flow to include more sensitive attributes
- Removing a transformation or protective step before data leaves the system
- Creating a new outward-facing path for sensitive or linkable personal data

Example:

```elixir
Req.post!("https://api.vendor.example/customers", json: %{
  email: user.email,
  phone: user.phone
})
```

Why this is `HIGH`:

- Personal data is being sent to an external destination
- The change crosses a stronger trust boundary than an internal-only flow

Another example:

```elixir
json(conn, %{
  user_id: user.id,
  email: user.email,
  ssn: user.ssn
})
```

Why this is `HIGH`:

- Sensitive data is now exposed in an outward-facing response
- The exposure is direct and potentially broad

Another example:

```elixir
# Before
json(conn, %{user_token: tokenize(user.email)})

# After
json(conn, %{email: user.email})
```

Why this is `HIGH`:

- A protective transformation was removed
- Raw personal data is now exposed where a transformed value was used before

## Detection Categories

PrivSignal commonly detects privacy-relevant changes in categories like these:

- Logging: personal data written to logs
- Telemetry and analytics: personal data sent to monitoring or event systems
- API responses: personal data returned from controllers or endpoints
- UI exposure: personal data assigned into rendered pages or live state
- External transfer: personal data sent to vendors, APIs, or third parties
- Persistence: personal data newly written to storage
- Data-shape expansion: more fields, more sensitive fields, or more linkable context included in an existing flow
- Protection changes: removal of masking, tokenization, redaction, or similar safeguards

## Quick Reference

| Score | Meaning | Typical reviewer reaction |
| --- | --- | --- |
| `NONE` | No privacy-relevant change detected | Usually no privacy follow-up needed |
| `LOW` | Privacy-relevant change with little or no added exposure | Quick review |
| `MEDIUM` | Meaningful expansion of handling or exposure | Deliberate review |
| `HIGH` | Material new exposure, sensitivity increase, or boundary crossing | Immediate focused review |

## Practical Review Guidance

When PrivSignal reports `MEDIUM` or `HIGH`, reviewers should usually ask:

- What personal data was added, exposed, stored, or transferred?
- Is the destination internal or external?
- Is the data sensitive, linkable, behavioral, or inferred?
- Was a new sink introduced?
- Did an existing sink begin receiving more data?
- Was a safeguard removed, weakened, or bypassed?
- If these are legitimate changes, are there privacy related documents that might need to be updated?

Those questions matter more than the exact mechanics of how the detection was produced.
