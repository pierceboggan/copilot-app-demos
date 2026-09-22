# Copilot app demos

Runnable demos of enterprise governance and observability for the GitHub Copilot app.

Two things live here. One is a complete enterprise-managed-settings configuration you can install on a laptop in under a minute, covering OpenTelemetry, sandboxing, and private plugin marketplaces. The other is an observability stack that turns the resulting telemetry into a Grafana dashboard.

There is also a third thing, which is the part I'd actually lead with in a demo: a validator that asks the Copilot runtime what it enforced, so you never have to take a documentation table on faith. Running it against the published docs turned up several discrepancies. Those are written up in [`enterprise-managed-settings/VALIDATION.md`](enterprise-managed-settings/VALIDATION.md).

## Layout

| Path | What it is |
| --- | --- |
| [`enterprise-managed-settings/`](enterprise-managed-settings/) | A worked `managed-settings.json`, per-team overrides, one-key scenario files, and install scripts for all three delivery channels |
| [`validate/`](validate/) | Two Node scripts that report what the runtime resolved and prove the permission rules bite |
| [`otel-dashboard/`](otel-dashboard/) | Collector, Prometheus, Tempo, and a Grafana dashboard built from a live capture |

## The 60-second version

Install a policy, restart the app, and ask the runtime what happened.

```bash
# 1. Block bypass ("YOLO") mode on this machine.
cd enterprise-managed-settings/deploy
./install-macos.sh ../scenarios/01-lock-down-bypass.json

# 2. Restart the GitHub Copilot app so it reloads policy at startup.

# 3. Ask the runtime what it actually enforced.
cd ../../validate
npm install
node validate-managed-settings.mjs
```

You should see `permissions` listed under the managed keys and `bypassPermissionsDisabled: true`. In the app, the Tool Permissions menu now refuses to stay on "Allow all" and raises a **Tool permissions limited** notice.

To undo it: `./enterprise-managed-settings/deploy/uninstall-macos.sh`.

## The observability version

```bash
cd otel-dashboard
docker compose up -d

cd ../enterprise-managed-settings/deploy
./install-macos.sh ../scenarios/07-otel-telemetry.json
# Restart the Copilot app, then use it for a few minutes.

open http://localhost:3000
```

No Docker? `otel-dashboard/local/run-tap.sh` downloads a standalone collector, listens on the same port, and writes every signal to a file you can read.

## Where the demo data comes from

Every metric name, label, and span attribute used in the dashboard was taken from a real capture on a real machine, not from the reference tables. The capture script and a redacted sample are in [`otel-dashboard/local/`](otel-dashboard/local/). That matters because a handful of the documented names turned out to be wrong, and a dashboard built from the docs would have rendered empty panels.

## Requirements

* GitHub Copilot app, or Copilot CLI 1.0.85 or newer
* A Copilot licence from an enterprise, for the server-managed parts
* Node 20+ for the validators
* Docker for the full dashboard stack, or nothing at all for the local tap
* Administrator rights for file-based and MDM delivery

## Caveats

These configurations name a fictional enterprise called Octo Industries and point at this repository for the plugin marketplace demo. Swap those before using any of it for real.

Nothing here is an official GitHub sample.
