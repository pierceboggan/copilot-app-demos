# Validating managed settings

Two scripts that answer questions you would otherwise have to guess at.

`validate-managed-settings.mjs` asks the Copilot runtime which keys it is enforcing and where they came from. `probe-enforcement.mjs` injects a permission policy and checks that it actually stops things.

```bash
npm install
node validate-managed-settings.mjs
node probe-enforcement.mjs
```

Both need a GitHub token. They use `GH_TOKEN`, then `GITHUB_TOKEN`, then `gh auth token`.

## validate-managed-settings.mjs

Creates a throwaway session with `enableManagedSettings: true`, which asks the runtime to fetch server and device policy the same way any client does. It listens for `session.managed_settings_resolved` and prints what came back.

```
Runtime
  binary: /opt/homebrew/bin/copilot

Device managed-settings file
  path: /Library/Application Support/GitHubCopilot/managed-settings.json
  present: yes — declares telemetry

Resolution
  source:                       device
  serverManaged (account/org):  false
  deviceManaged (MDM/file):     true
  clientManaged (SDK host):     false
  policyHelperManaged:          false
  failClosed:                   false
  bypassPermissionsDisabled:    false

Keys under enterprise management
  model                    not set
  permissions              not set
  telemetry                MANAGED
  remoteControl            MANAGED
  ...

Effective settings the runtime enforced
  { ... }
```

Three columns in that output do most of the work.

`source` and the per-channel booleans tell you which delivery method won. If you installed a file and see `deviceManaged: false`, the file is not being read, and the usual cause on macOS is ownership or permissions rather than JSON.

`DECLARED BUT NOT MANAGED` next to a key means your policy file names it but the runtime did not put it under management. That is the signal that a key is unsupported on this client or was rejected.

`failClosed: true` means policy could not be determined and the runtime applied restrictions anyway. Restrictions in that state are real, but they are not your administrator's intent, and `settings` may be empty.

Flags: `--json` for machine-readable output, `--debug` to list every event the session emitted.

To point at a specific runtime, set `COPILOT_CLI_PATH`. By default the script prefers a `copilot` on your `PATH` over the runtime bundled with the SDK, because managed settings are a moving target and the bundled one can lag.

## probe-enforcement.mjs

The permission keys are the hardest to verify by reading a config, and the most embarrassing to get wrong. This script injects a policy through the SDK's host channel, which the runtime validates with the same parser it uses for fetched policy, then tries to violate it.

The trick is that it registers a permission handler that approves everything. Anything that still prompts or still refuses did so because of policy.

```
--- allow — Shell(echo *)     (expected: runs with no prompt)
  permission prompts raised: 0
  agent said: Output: `managed-allow-ok`

--- ask   — Shell(git push *)  (expected: prompts even though the host approves everything)
  permission prompts raised: 1
    tool=shell managedApprovalRequired=true
  agent said: ...

--- deny  — Shell(rm -rf *)    (expected: refused outright)
  permission prompts raised: 0
  agent said: The command was denied by policy: `Shell(rm -rf *)`
```

`managedApprovalRequired=true` is the runtime telling the client that this prompt exists because of enterprise policy, so a client can say so rather than showing a generic approval dialog.

Edit the `INJECTED` constant at the top to try your own rules. Malformed rules are rejected at session creation, which is a fast way to check selector syntax.

Note that host-injected policy composes *restrictively* with whatever is already on the machine. It can tighten but never loosen. If your laptop is enrolled in corporate MDM, that policy still applies underneath.

## Things that cost me time

The `session.managed_settings_resolved` event arrives a tick after the `session.create` RPC resolves, not before it. Checking synchronously after `createSession` finds nothing, even though the event is the first one the session emits. Both scripts poll briefly.

There is no `getManagedSettings` RPC on the session. Subscribing to the event is the only way to see this.

The event is ephemeral. It is delivered to live subscribers and never written to the session event log, so you cannot go back and read it off a finished session.
