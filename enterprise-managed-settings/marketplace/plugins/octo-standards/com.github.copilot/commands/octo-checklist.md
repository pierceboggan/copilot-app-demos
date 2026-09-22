---
description: Run the Octo Industries pre-merge checklist against the current change.
---

Review the current diff against the Octo Industries pre-merge checklist and
report what passes, what fails, and what you could not determine.

1. Secrets. No credential, token, or key is committed, logged, or interpolated
   into a shell string.
2. Dependencies. Any new dependency is pinned and comes from an approved
   registry.
3. Error handling. Failures are surfaced rather than swallowed, and error
   messages do not leak internal detail to an end user.
4. Tests. Behaviour that changed has a test covering it.
5. Backwards compatibility. Any changed public interface, stored schema, or
   serialized payload is either compatible or has a migration.

For each item, say pass, fail, or unknown, and give the file and line that
justifies the answer. Do not report a pass you cannot point at.
