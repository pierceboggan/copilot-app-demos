#!/usr/bin/env node
/**
 * Prints the enterprise managed settings that the Copilot runtime actually
 * resolved for a session.
 *
 * Why this exists: `copilot/managed-settings.json` is a contract between an
 * administrator and a client, and the only way to know a key landed is to ask
 * the runtime what it enforced. The runtime answers with the
 * `session.managed_settings_resolved` event, which carries `managedKeys` (the
 * keys under enterprise management) and `settings` (the effective values).
 *
 * That event fires before `session.start`, so it is subscribed through the
 * `onEvent` callback passed at session creation rather than `session.on(...)`.
 *
 * Usage:
 *   npm install
 *   node validate-managed-settings.mjs
 *   node validate-managed-settings.mjs --json > resolved.json
 */

import { CopilotClient, RuntimeConnection } from "@github/copilot-sdk";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const jsonOnly = process.argv.includes("--json");
const debug = process.argv.includes("--debug");
const log = (...a) => {
    if (!jsonOnly) console.log(...a);
};

const FILE_PATHS = {
    darwin: "/Library/Application Support/GitHubCopilot/managed-settings.json",
    win32: `${process.env.ProgramFiles ?? "C:\\Program Files"}\\GitHubCopilot\\managed-settings.json`,
    linux: "/etc/github-copilot/managed-settings.json",
};

function resolveToken() {
    if (process.env.GH_TOKEN) return process.env.GH_TOKEN;
    if (process.env.GITHUB_TOKEN) return process.env.GITHUB_TOKEN;
    try {
        return execFileSync("gh", ["auth", "token"], { encoding: "utf8" }).trim();
    } catch {
        return undefined;
    }
}

/**
 * The SDK bundles its own runtime, which can lag the CLI you have installed.
 * Managed settings are an experimental surface, so prefer the newest runtime on
 * the machine and fall back to the bundled one.
 */
function resolveRuntime() {
    const explicit = process.env.COPILOT_CLI_PATH;
    const candidates = [explicit, "/opt/homebrew/bin/copilot", "/usr/local/bin/copilot"].filter(
        Boolean,
    );
    for (const path of candidates) {
        if (existsSync(path)) return { connection: RuntimeConnection.forStdio({ path }), path };
    }
    try {
        const which = execFileSync("which", ["copilot"], { encoding: "utf8" }).trim();
        if (which) return { connection: RuntimeConnection.forStdio({ path: which }), path: which };
    } catch {
        /* fall through to the bundled runtime */
    }
    return { connection: undefined, path: "(runtime bundled with @github/copilot-sdk)" };
}

function readDeviceFile() {
    const path = FILE_PATHS[process.platform];
    if (!path) return { path: undefined, contents: undefined };
    try {
        return { path, contents: JSON.parse(readFileSync(path, "utf8")) };
    } catch {
        return { path, contents: undefined };
    }
}

const ALL_DOCUMENTED_KEYS = [
    "model",
    "permissions",
    "enabledPlugins",
    "extraKnownMarketplaces",
    "strictKnownMarketplaces",
    "telemetry",
    "remoteControl",
    "allowedMcpServers",
    "deniedMcpServers",
    "sandbox",
];

async function main() {
    const token = resolveToken();
    if (!token) {
        console.error(
            "No GitHub token found. Set GH_TOKEN, or sign in with `gh auth login`.",
        );
        process.exit(1);
    }

    const device = readDeviceFile();
    const runtime = resolveRuntime();
    log("Runtime");
    log("  binary:", runtime.path);
    log("");
    log("Device managed-settings file");
    log("  path:", device.path ?? "(unsupported platform)");
    log(
        "  present:",
        device.contents ? `yes — declares ${Object.keys(device.contents).join(", ")}` : "no",
    );
    log("");

    const client = new CopilotClient({
        connection: runtime.connection,
        gitHubToken: token,
        logLevel: "none",
        workingDirectory: mkdtempSync(join(tmpdir(), "copilot-ems-")),
    });

    let resolved;
    const enforced = [];
    const seenEventTypes = new Set();

    await client.start();
    const session = await client.createSession({
        clientName: "managed-settings-validator",
        gitHubToken: token,
        // Ask the runtime to self-fetch server (account/org) and device policy.
        enableManagedSettings: true,
        onEvent: (event) => {
            seenEventTypes.add(event.type);
            if (event.type === "session.managed_settings_resolved") resolved = event.data;
            if (event.type === "session.managed_settings_enforced") enforced.push(event.data);
        },
    });

    // `session.managed_settings_resolved` is dispatched immediately after the
    // `session.create` RPC settles rather than before it, so give the runtime a
    // moment to deliver it.
    for (let waited = 0; !resolved && waited < 10_000; waited += 100) {
        await new Promise((r) => setTimeout(r, 100));
    }

    if (debug) {
        log("Event types observed during session creation:");
        for (const t of [...seenEventTypes].sort()) log("  " + t);
        log("");
    }

    if (!resolved) {
        console.error(
            "The runtime never emitted session.managed_settings_resolved.\n" +
                "Either the runtime predates the managed-settings surface, or no\n" +
                "managed policy applies to this account and device. Re-run with --debug\n" +
                "to list the events the session did emit.",
        );
        await session.disconnect().catch(() => {});
        await client.stop();
        process.exit(2);
    }

    if (jsonOnly) {
        console.log(JSON.stringify({ resolved, enforced, deviceFile: device }, null, 2));
    } else {
        report(resolved, device);
    }

    await session.disconnect().catch(() => {});
    await client.stop();
}

function report(r, device) {
    const managed = new Set(r.managedKeys ?? []);

    log("Resolution");
    log("  source:                      ", r.source);
    log("  serverManaged (account/org): ", r.serverManaged);
    log("  deviceManaged (MDM/file):    ", r.deviceManaged);
    log("  clientManaged (SDK host):    ", r.clientManaged ?? false);
    log("  policyHelperManaged:         ", r.policyHelperManaged ?? false);
    log("  failClosed:                  ", r.failClosed);
    log("  bypassPermissionsDisabled:   ", r.bypassPermissionsDisabled);
    if (r.permissionsAllowIntersected !== undefined) {
        log("  permissionsAllowIntersected: ", r.permissionsAllowIntersected);
    }
    if (r.sandboxEnabledByUndeterminedPolicy !== undefined) {
        log("  sandboxEnabledByUndeterminedPolicy:", r.sandboxEnabledByUndeterminedPolicy);
    }
    log("");

    log("Keys under enterprise management");
    if (managed.size === 0) {
        log("  (none — no managed policy is in force for this account or device)");
    }
    for (const key of ALL_DOCUMENTED_KEYS) {
        const declaredOnDevice = device.contents && key in device.contents;
        let verdict;
        if (managed.has(key)) verdict = "MANAGED";
        else if (declaredOnDevice) verdict = "DECLARED BUT NOT MANAGED";
        else verdict = "not set";
        log(`  ${key.padEnd(24)} ${verdict}`);
    }
    const extra = [...managed].filter((k) => !ALL_DOCUMENTED_KEYS.includes(k));
    if (extra.length) {
        log("");
        log("  Managed keys not in the published reference:", extra.join(", "));
    }
    log("");

    log("Effective settings the runtime enforced");
    log(
        r.settings
            ? JSON.stringify(r.settings, null, 2)
                  .split("\n")
                  .map((l) => "  " + l)
                  .join("\n")
            : "  (absent — no managed policy in force, or fail-closed with no values)",
    );
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
