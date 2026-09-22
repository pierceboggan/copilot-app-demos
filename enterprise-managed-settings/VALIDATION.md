# Validation: what actually works

The reference table for enterprise-managed settings lists twelve keys and marks each one supported or unsupported per client. This is a record of checking those claims against a real GitHub Copilot app and a real Copilot CLI, rather than reading the table and hoping.

Most of it holds up. Two things did not.

**Tested against:** GitHub Copilot app bundling Copilot runtime `1.0.87-0`, Copilot CLI `1.0.88-0` standalone, `@github/copilot-sdk` `1.0.14`, macOS 15 arm64. September 2026.

## Method

Three techniques, because no single one covers every key.

**Ask the runtime what it resolved.** Copilot emits `session.managed_settings_resolved` at session start. It carries `managedKeys` (the keys under enterprise management), `settings` (the effective values), and a boolean per delivery channel. That is the authoritative answer to "did my key land", and it is what [`validate/validate-managed-settings.mjs`](../validate/validate-managed-settings.mjs) prints.

One wrinkle worth recording: the event arrives a tick *after* the `session.create` RPC settles, not before it, despite the schema documentation describing it as firing before `session.start`. Subscribing via the creation-time `onEvent` callback and then checking synchronously finds nothing. The validator waits for it.

**Inject a policy and watch it bite.** The SDK exposes a host-injected managed-settings layer that the runtime parses with the same code path as fetched policy. That makes it possible to exercise `permissions.deny`, `ask`, and `allow` on a laptop without root and without an enterprise. [`validate/probe-enforcement.mjs`](../validate/probe-enforcement.mjs) does this, deliberately registering an approve-everything permission handler so that any prompt or refusal that survives must have come from policy.

**Capture the telemetry.** An OpenTelemetry Collector on `127.0.0.1:4319`, a managed `telemetry` setting pointing at it, then read what arrives. See [`otel-dashboard/local/`](../otel-dashboard/local/).

## Summary

| Key | Docs say (app) | Found | Notes |
| --- | --- | --- | --- |
| `permissions.deny` | Supported | **Confirmed** | Refused with the rule quoted back, no prompt raised |
| `permissions.ask` | Supported | **Confirmed** | Prompted even against an approve-all host handler |
| `permissions.allow` | Supported | **Confirmed** | Ran with zero prompts |
| `permissions.disableBypassPermissionsMode` | Supported | **Confirmed** | `bypassPermissionsDisabled: true`; app caps the permission menu |
| `remoteControl` | Supported | **Confirmed** | Resolved from an MDM plist; has an undocumented subkey |
| `telemetry` | **Not supported** | **Works anyway** | App sessions exported full traces and metrics. See below |
| `sandbox` | Not supported | Correct, with caveats | The app has its own unrelated sandbox features |
| `enabledPlugins` | Supported | **Confirmed (locally)** | Marketplace registered, plugin installed, skill and command loaded |
| `extraKnownMarketplaces` | Supported | **Confirmed (locally)** | Directory source exercised via `copilot plugin marketplace add` |
| `strictKnownMarketplaces` | Supported | Not exercised | Needs a policy server to test meaningfully |
| `model` | Supported | Not exercised | No managed model policy available to test against |
| `allowedMcpServers` / `deniedMcpServers` | Supported | Not exercised | Resolved by the runtime, not parsed by the app |

"Not exercised" means I could not construct a test that would have produced a falsifiable result, usually because it needs an enterprise policy server. It is not evidence against the documentation.

## Findings

### `permissions.deny`, `ask`, and `allow` all work, and `ask` cannot be talked out of

Injected policy:

```json
{
  "permissions": {
    "disableBypassPermissionsMode": "disable",
    "deny": ["Shell(rm -rf *)", "Read(~/.ssh/**)"],
    "ask": ["Shell(git push *)"],
    "allow": ["Shell(echo *)"]
  }
}
```

Resolution reported `source: client`, `managedKeys: permissions`, `bypassPermissionsDisabled: true`.

Then, with a permission handler that returns approve for absolutely everything:

```
--- allow — Shell(echo *)
  permission prompts raised: 0
  agent said: Output: `managed-allow-ok`

--- ask   — Shell(git push *)
  permission prompts raised: 1
    tool=shell managedApprovalRequired=true
  agent said: Output: fatal: not a git repository ...

--- deny  — Shell(rm -rf *)
  permission prompts raised: 0
  agent said: The command was denied by policy: `Shell(rm -rf *)`
```

Three things are worth pulling out of that.

The `ask` rule raised a prompt despite the host trying to rubber-stamp everything, and the runtime flagged it with `managedApprovalRequired: true` so a client can explain *why* it is asking. The `deny` rule refused without raising a prompt at all, which is the right shape: there is nothing for a user to approve. And the `allow` rule ran clean, confirming that declaring an allowlist does not silently force everything else into prompting when the other lists are also present.

The SDK also refuses to let a host be careless here. Its `approveAll` helper throws outright if managed settings are enabled, and returns no-result when a request carries `managedApprovalRequired`.

### `disableBypassPermissionsMode` has an undocumented second value

The reference documents `"disable"`. The runtime also accepts `"allow-auto-only"`, which permits automatic bypass while blocking full allow-all. It is a named constant in the SDK:

```ts
export const DisableBypassPermissionsModes = {
  Disable: "disable",
  AllowAutoOnly: "allow-auto-only",
} as const;
```

Unknown values are forwarded to the runtime rather than rejected, so a newer policy fails closed on an older client instead of being ignored.

In the app, this key does more than block a menu item. The app keeps the permission mode the user *asked* for separately from the mode the runtime granted, and re-asserts it whenever policy stops capping the session. It distinguishes a genuine enterprise policy from a fail-closed fallback using the `failClosed` flag on the same event, so a transient failure to fetch policy does not permanently strand a session on "Always ask". The user-visible result of a real policy is a **Tool permissions limited** notice carrying the runtime's own explanation.

### `telemetry`

**The reference table marks this unsupported for the GitHub Copilot app. On a real machine, it works.**

Setup was a collector on `127.0.0.1:4319` and a file-based policy containing only:

```json
{ "telemetry": { "enabled": true, "endpoint": "http://127.0.0.1:4319", "protocol": "http/protobuf", "captureContent": false } }
```

The app was not restarted or specially configured. Over a normal working session the collector received 2,215 spans and 14 metric instruments, grouped into fifteen distinct resource attribute sets. Separating them by resource attributes makes the source unambiguous:

| Resource attributes | Emitter |
| --- | --- |
| `service.name=github-copilot`, `service.version=1.0.87-0`, `agency.session_id=…`, `agency.run_kind=user_session` | GitHub Copilot app sessions |
| `service.name=github-copilot`, `service.version=1.0.88-0` | A standalone `copilot -p` run from a terminal |

The app-tagged resources carried `gen_ai.conversation.id` values matching live app sessions, plus `execute_tool` spans for tools that only exist inside the app. They also carried `session.timing.*` spans covering the app's own session-provisioning phases, which the standalone CLI never emitted.

The mechanism is not mysterious. The app runs Copilot CLI underneath, that CLI reads device-channel managed settings at startup like any other client, and it exports accordingly. The practical consequence is that an administrator who sets `telemetry` expecting the app to be exempt will find app sessions in their collector.

A narrower reading of the table might be that the *app process itself* has no managed-telemetry path of its own, which is true. Its only independent OTel code path is an internal performance trace that writes to a file. That distinction is invisible to an administrator looking at a dashboard.

### `remoteControl` has an undocumented subkey

Resolved successfully from an MDM-delivered plist at `/Library/Managed Preferences/<user>/com.github.copilot.plist`, confirming both that the key works and that macOS MDM delivery works.

The documentation describes `mode` and `githubDotComOrganizations`. The effective settings also contained `githubEnterpriseCloudDomains`, an array of GHEC data-residency hosts. That makes sense for an enterprise on `*.ghe.com` that needs SSO-gated remote control scoped to its own tenant, and it is missing from the reference.

### The plugin chain works, with one undocumented composition rule

The marketplace in [`marketplace/`](marketplace/) was built from the reference and then run against a real CLI:

```
$ copilot plugin marketplace add "$PWD/marketplace"
Marketplace "octo-internal" added successfully.

$ copilot plugin install octo-standards@octo-internal
Plugin "octo-standards" installed successfully. Installed 1 skill.

$ copilot skill list
Plugin skills:
  secure-defaults - ...
  octo-checklist  - ...
```

The reference describes `metadata.pluginRoot` and a plugin entry's `source` separately and never says how they combine. They concatenate. With `pluginRoot: "plugins"`, a `source` of `./plugins/octo-standards` resolves to `plugins/plugins/octo-standards` and the install fails naming a path that appears nowhere in the manifest. The correct entry is `./octo-standards`.

That is a five-minute debugging detour the first time, and the error message does not point at the cause.

### `sandbox`

The documentation is right that the managed `sandbox` key is scoped to Copilot CLI. Two things make it easy to think otherwise.

The app has its own sandbox features, including a `/sandbox` command and per-project sandbox preferences. Those are unrelated to the managed key and are not governed by it.

And the runtime reports sandbox state on the managed-settings event regardless of client. `sandboxEnabledByUndeterminedPolicy` distinguishes a sandbox that is on because policy demands it from one that is on because policy could not be determined, which is precisely the distinction you need to explain a surprise to a user. The runtime also emits a `github.copilot.sandbox.operation.count` metric that appears in app-originated telemetry.

## Documentation discrepancies

Collected in one place, since these are the actionable ones.

| Where | Documented | Actual |
| --- | --- | --- |
| Reference table, `telemetry` row | Not supported in the GitHub Copilot app | App sessions export traces and metrics through device-channel policy |
| `chat` and `invoke_agent` span attributes | `gen_ai.usage.cache_creation.input_tokens` | `gen_ai.usage.cache_write.input_tokens`. Zero occurrences of the documented name across 2,215 spans; 167 of the actual one |
| `disableBypassPermissionsMode` | `"disable"` | Also accepts `"allow-auto-only"` |
| `remoteControl` | `mode`, `githubDotComOrganizations` | Also `githubEnterpriseCloudDomains` |
| `marketplace.json` | `metadata.pluginRoot` and plugin `source` documented separately | They concatenate; `source` is relative to `pluginRoot` |

A dashboard built from the documented cache attribute renders an empty panel, which is how this one surfaced.

## Undocumented surface

Present in real telemetry, absent from the reference. Useful, but treat as unstable.

**Metrics**

* `gen_ai.execute_tool.duration` (histogram, seconds) with labels `gen_ai.tool.name`, `gen_ai.tool.type`, `gen_ai.agent.name`, `error.type`
* `github.copilot.sandbox.operation.count` (counter) with labels for decision kind, control, outcome, enforcement point, and platform

**Resource attributes, app only**

* `agency.session_id` — the app's session identifier
* `agency.run_kind` — `user_session` for interactive work

These are genuinely useful. `agency.session_id` is the only clean way to separate app traffic from CLI traffic in a shared collector.

**Span attributes**

On `chat`: `gen_ai.usage.reasoning.output_tokens`, `gen_ai.request.reasoning.level`, `gen_ai.request.previous_response.id`, `github.copilot.service_request_id`.

On `invoke_agent`: `github.copilot.agent.type`, `github.copilot.context.custom_agent_names`, `github.copilot.context.mcp_server_names`, `github.copilot.context.skills`.

On `execute_tool`: `github.copilot.tool.parameters.skill_name`, `github.copilot.tool.parameters.mcp_server_name_hash`.

**Spans**

A `session.provisioning` span and a large family of `session.timing.*` spans, each carrying phase, ordinal, start offset, and duration. These come from the app and describe how long each stage of session startup took. Handy for diagnosing a slow app, noisy for anything else, and worth filtering out at the collector if you are paying per span.

## Reproducing

```bash
cd validate
npm install
node validate-managed-settings.mjs --debug    # resolution and channels
node probe-enforcement.mjs                    # deny / ask / allow
```

For the telemetry findings:

```bash
cd otel-dashboard/local
./run-tap.sh                                  # collector on 127.0.0.1:4319
# install scenarios/07-otel-telemetry.json, restart the app, use it
node summarize-capture.mjs                    # span names, metrics, labels
```

For the plugin chain:

```bash
cd enterprise-managed-settings
export COPILOT_HOME=$(mktemp -d)              # keep your real config out of it
copilot plugin marketplace add "$PWD/marketplace"
copilot plugin install octo-standards@octo-internal
copilot skill list
```
