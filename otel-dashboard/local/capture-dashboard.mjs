#!/usr/bin/env node
/**
 * Capture the Copilot Grafana dashboard: a full-page screenshot, per-row
 * closeups, and a short video walkthrough.
 *
 * Run it against a live stack (see otel-dashboard/README.md). Grafana is
 * anonymous-admin, so there is no login step.
 *
 *   node capture-dashboard.mjs [outputDir]
 */

import { chromium } from "playwright";
import { mkdirSync } from "node:fs";
import { join } from "node:path";

const OUT = process.argv[2] ?? "./media";
const GRAFANA = process.env.GRAFANA_URL ?? "http://127.0.0.1:3000";
const DASH = `${GRAFANA}/d/copilot-agent-overview/github-copilot-agent-overview`;
const RANGE = "from=now-3h&to=now";

mkdirSync(OUT, { recursive: true });

/**
 * Grafana renders panels asynchronously and reports readiness through a
 * data attribute on each panel. Waiting on that beats a fixed sleep, which
 * either flakes or wastes time.
 */
async function waitForPanels(page, { minPanels = 6, timeout = 60_000 } = {}) {
    await page.waitForSelector("[data-testid='data-testid panel content']", { timeout });
    await page.waitForFunction(
        (min) => {
            const panels = document.querySelectorAll(
                "[data-testid='data-testid panel content']",
            );
            if (panels.length < min) return false;
            // Any panel still showing a loading bar means we are not settled.
            const loading = document.querySelectorAll(
                "[aria-label='Panel loading bar'], .panel-loading",
            );
            return loading.length === 0;
        },
        minPanels,
        { timeout },
    );
    // Let the final animation frame land.
    await page.waitForTimeout(2500);
}

/**
 * Grafana only mounts panels once they scroll into view, so a full-page
 * screenshot taken straight after load leaves every row below the fold blank.
 * Walk to the bottom, let those panels query, then come back to the top.
 */
async function realizeLazyPanels(page) {
    const height = await page.evaluate(() => document.body.scrollHeight);
    for (let y = 0; y < height; y += 400) {
        await page.mouse.wheel(0, 400);
        await page.waitForTimeout(300);
    }
    await page.waitForTimeout(2500);
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(1500);
}

async function main() {
    const browser = await chromium.launch();

    // Screenshots: retina scale for crisp README images.
    const shotCtx = await browser.newContext({
        viewport: { width: 1600, height: 1200 },
        deviceScaleFactor: 2,
        colorScheme: "dark",
    });
    const page = await shotCtx.newPage();

    console.log("Loading dashboard…");
    await page.goto(`${DASH}?${RANGE}&kiosk`, { waitUntil: "networkidle" });
    await waitForPanels(page);
    await realizeLazyPanels(page);

    console.log("Full dashboard →", join(OUT, "dashboard-full.png"));
    await page.screenshot({ path: join(OUT, "dashboard-full.png"), fullPage: true });

    console.log("Above the fold →", join(OUT, "dashboard-overview.png"));
    await page.screenshot({ path: join(OUT, "dashboard-overview.png") });

    // Per-panel closeups. Grafana exposes a stable per-title test id.
    const closeups = [
        ["Token throughput by model", "panel-token-throughput.png"],
        ["Model call latency", "panel-latency.png"],
        ["Tool latency and failures", "panel-tool-table.png"],
        ["Busiest tools", "panel-busiest-tools.png"],
    ];
    for (const [title, file] of closeups) {
        const panel = page.locator(`[data-testid="data-testid Panel header ${title}"]`).first();
        if ((await panel.count()) === 0) {
            console.log(`  (skipped ${title}: not found)`);
            continue;
        }
        await panel.scrollIntoViewIfNeeded();
        await page.waitForTimeout(1200);
        console.log("Panel →", file);
        await panel.screenshot({ path: join(OUT, file) });
    }

    await shotCtx.close();

    // Video: a slow scroll through the dashboard, recorded at 1080p.
    console.log("Recording walkthrough…");
    const vidCtx = await browser.newContext({
        viewport: { width: 1920, height: 1080 },
        colorScheme: "dark",
        recordVideo: { dir: join(OUT, "video-raw"), size: { width: 1920, height: 1080 } },
    });
    const vp = await vidCtx.newPage();
    await vp.goto(`${DASH}?${RANGE}&kiosk`, { waitUntil: "networkidle" });
    await waitForPanels(vp);
    await realizeLazyPanels(vp);
    await vp.waitForTimeout(1500);

    // Ease down the page so the recording is readable rather than a jump cut.
    const height = await vp.evaluate(() => document.body.scrollHeight);
    for (let y = 0; y < height; y += 120) {
        await vp.mouse.wheel(0, 120);
        await vp.waitForTimeout(110);
    }
    await vp.waitForTimeout(1500);
    await vp.evaluate(() => window.scrollTo({ top: 0, behavior: "smooth" }));
    await vp.waitForTimeout(2500);

    await vidCtx.close(); // flushes the video file
    await browser.close();
    console.log("Done. Raw video in", join(OUT, "video-raw"));
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
