---
name: secure-defaults
description: Use when writing or reviewing code that handles credentials, network calls, subprocess execution, or user input. Applies the Octo Industries secure-default rules.
---

# Secure defaults

House rules. They exist because each one has cost us an incident.

## Credentials

Read secrets from the environment or the platform secret store. Never from a
file in the repository, and never from a default argument value.

Do not log a secret, even redacted. Redaction bugs are the most common way
secrets reach a log aggregator.

When a secret must cross a process boundary, pass it through the environment
rather than an argument. Arguments are visible in the process table.

## Network calls

Every outbound call gets a timeout. A call without one will eventually hang and
take a worker with it.

Verify TLS. If a certificate check is failing, fix the certificate.

Prefer an allowlist of hosts over a denylist of hosts.

## Subprocess execution

Pass arguments as a list. Never build a shell string from user input, and avoid
`shell=True` and its equivalents.

If a shell really is required, quote every interpolated value with the
platform's own quoting helper.

## User input

Validate at the boundary, not at the point of use. By the time a value reaches
business logic it should already be the right type and shape.

Parameterize every database query. String interpolation into SQL is never
acceptable, including for identifiers you believe are internal.
