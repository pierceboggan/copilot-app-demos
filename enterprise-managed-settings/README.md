# Enterprise-managed settings

An administrator writes a JSON file. Every Copilot client in the enterprise obeys it. That is the whole idea, and the rest is detail about where the file lives, which keys each client understands, and how to carve out exceptions for teams that need them.

This directory holds a worked configuration plus the tooling to install and verify it.

## What's here

```
copilot/
  managed-settings.json     the enterprise baseline
  team-mappings.json        which team gets which override file
  teams/
    ai-pioneers.json        loosens the model default, widens the MCP allowlist
    regulated.json          pins a model, moves more operations to "ask"

scenarios/                  one key per file, for demoing a single behaviour
  01-lock-down-bypass.json
  02-permission-rules.json
  03-default-model.json
  04-private-marketplace.json
  05-mcp-allowlist.json
  06-remote-control.json
  07-otel-telemetry.json
  08-sandbox.json

deploy/
  install-macos.sh          file-based delivery, macOS
  install-linux.sh          file-based delivery, Linux
  install-windows.ps1       file-based delivery, Windows
  uninstall-macos.sh
  mdm/
    com.github.copilot.mobileconfig    macOS MDM payload
    windows-GitHubCopilot.reg          Windows policy registry keys

VALIDATION.md               what actually works, tested against a real client
```

## Three ways to deliver a policy

Pick based on who owns the decision and how fast you need to iterate.

**Server-managed** puts `copilot/managed-settings.json` in a `.github-private` repository owned by an organization in your enterprise. Clients pick it up within about an hour, or immediately on restart. It is the only channel that supports per-team overrides, and the only one that reaches the Copilot cloud agent. It applies to people who get their Copilot licence from your enterprise.

**MDM** writes the same logical keys as operating-system-managed values: `HKEY_LOCAL_MACHINE\SOFTWARE\Policies\GitHubCopilot` on Windows, forced managed preferences for the `com.github.copilot` domain on macOS. Every value is a string, nested keys use dot notation, and anything structured is JSON text inside that string. See the payloads in `deploy/mdm/`. This reaches a device regardless of where the person's licence came from, and it outranks the other channels.

**File-based** drops the JSON at a fixed path on disk. On macOS that is `/Library/Application Support/GitHubCopilot/managed-settings.json`, owned by root, not group- or world-writable, not a symlink. This is the one to use for a demo, because it needs no enterprise and no MDM server. It is also the only device-channel option on Linux.

When more than one channel is present, MDM wins, then server, then file, then the user's own settings. Sandbox settings and the three permission lists are the exception: those compose toward whichever answer is more restrictive, so a deny rule from any channel denies for everyone.

## Running the demo

Install one scenario, restart the client, verify.

```bash
cd deploy
./install-macos.sh ../scenarios/01-lock-down-bypass.json
# restart the GitHub Copilot app
cd ../../validate && npm install && node validate-managed-settings.mjs
```

The installer backs up whatever policy was already on the machine and restores it when you run `uninstall-macos.sh`. Worth knowing if your laptop is already enrolled in corporate MDM.

To demo the full baseline rather than one key, pass `../copilot/managed-settings.json` instead. Be aware that it enables the sandbox and points telemetry at `127.0.0.1:4319`, so start the collector first or telemetry export will just fail quietly.

## Overriding for teams

Server-managed deployments can vary a key by enterprise team. Mark the key overridable in the baseline:

```json
{
  "model": { "overridable": "auto" },
  "permissions": {
    "disableBypassPermissionsMode": { "overridable": "disable" }
  }
}
```

The value inside `overridable` is the default for everyone whose team does not say otherwise. Then map teams to files in `team-mappings.json`, keyed by file name so one file can serve several teams:

```json
{
  "ai-pioneers.json": ["ai-pioneers"],
  "regulated.json": ["payments-platform", "identity-core"]
}
```

And write the team's values in `teams/<name>.json` using ordinary syntax. `"unmanaged"` removes the enterprise default for that team entirely.

Only `model`, the four `permissions` subkeys, `allowedMcpServers`, and `deniedMcpServers` accept the `overridable` wrapper. `enabledPlugins` and `extraKnownMarketplaces` behave differently: a team file adds to the enterprise baseline rather than replacing it. Everything else stays fixed at the enterprise level.

Someone on two teams gets the least restrictive value of the two, and the enterprise baseline still sits underneath.

## The three headline keys

### OpenTelemetry

```json
{
  "telemetry": {
    "enabled": true,
    "endpoint": "http://127.0.0.1:4319",
    "protocol": "http/protobuf",
    "captureContent": false,
    "lockCaptureContent": true
  }
}
```

`captureContent` decides whether prompts, responses, and tool arguments ride along. Leave it off unless the collector is somewhere you would be comfortable storing source code. `lockCaptureContent` stops a developer turning it on locally.

The reference table says this key is unsupported in the GitHub Copilot app. That turns out not to match the behaviour on a real machine, and the reasons are in [VALIDATION.md](VALIDATION.md#telemetry). Pair this with [`../otel-dashboard/`](../otel-dashboard/) to see the data land.

### Sandbox

```json
{
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowBypass": false,
    "sandboxMcpServers": true
  }
}
```

Managed sandbox settings impose a floor rather than a default. A `true` on a force-on setting enforces it; a `false` leaves the user's own configuration alone. For capability settings it runs the other way, where `false` prohibits and `true` leaves things as they were. Managed path grants narrow the user's grants, and managed denied paths add to the user's denials.

`failIfUnavailable` is the one worth understanding. On its own it does nothing. Combined with `enabled`, it means Copilot blocks model and tool execution outright when it cannot compile or enforce the policy, instead of quietly running unsandboxed.

### Private plugin marketplace

```json
{
  "extraKnownMarketplaces": {
    "octo-internal": {
      "source": { "source": "github", "repo": "OWNER/REPO", "ref": "main", "path": "marketplace" },
      "autoUpdate": true
    }
  },
  "strictKnownMarketplaces": [
    { "source": "github", "repo": "OWNER/REPO" }
  ],
  "enabledPlugins": { "octo-standards@octo-internal": true }
}
```

`extraKnownMarketplaces` adds a source. `strictKnownMarketplaces` restricts installation to only the sources you list, and an empty array locks plugin installation down completely. `enabledPlugins` then force-installs or force-blocks individual plugins, keyed `PLUGIN@MARKETPLACE`.

One practical snag: a force-installed plugin still needs the user to have access to wherever it is hosted. Private repository, private plugin, and the install fails for anyone without read access.

## Verifying

Guessing whether a key landed is the slow way to run a demo. Ask the runtime instead:

```bash
cd ../validate
npm install
node validate-managed-settings.mjs     # what got resolved, and from which channel
node probe-enforcement.mjs             # prove deny / ask / allow actually bite
```

See [`../validate/README.md`](../validate/README.md).

## Further reading

* [Getting started with enterprise-managed settings](https://docs.github.com/copilot/how-tos/administer-copilot/manage-for-enterprise/use-managed-settings/get-started)
* [Enterprise managed settings reference](https://docs.github.com/copilot/reference/enterprise-administrators/enterprise-managed-settings)
* [Choosing how to deploy managed settings](https://docs.github.com/copilot/how-tos/administer-copilot/manage-for-enterprise/use-managed-settings/deploy-managed-settings)
* [Overriding settings for teams](https://docs.github.com/copilot/how-tos/administer-copilot/manage-for-enterprise/use-managed-settings/override-settings-for-teams)
