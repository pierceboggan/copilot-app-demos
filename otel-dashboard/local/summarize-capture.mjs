#!/usr/bin/env node
/**
 * Summarizes a capture from the local OTLP tap: which spans, metrics, and
 * resource attributes a Copilot client actually sent.
 *
 * Useful before you build a dashboard, and useful as evidence when a
 * documented signal turns out to be absent (or an undocumented one turns up).
 *
 *   node summarize-capture.mjs
 *   node summarize-capture.mjs captured/traces.jsonl captured/metrics.jsonl
 */

import { readFileSync, existsSync } from "node:fs";

const args = process.argv.slice(2);
const traceFile = args[0] ?? "captured/traces.jsonl";
const metricFile = args[1] ?? "captured/metrics.jsonl";

const attrValue = (v) => (v ? Object.values(v)[0] : undefined);

function* batches(path) {
    if (!existsSync(path)) return;
    for (const line of readFileSync(path, "utf8").trim().split("\n")) {
        if (line) yield JSON.parse(line);
    }
}

function summarizeTraces(path) {
    const spans = new Map();
    const resources = new Map();
    let total = 0;

    for (const batch of batches(path)) {
        for (const rs of batch.resourceSpans ?? []) {
            const attrs = {};
            for (const a of rs.resource?.attributes ?? []) attrs[a.key] = attrValue(a.value);
            const key = JSON.stringify(attrs);
            resources.set(key, (resources.get(key) ?? 0) + 1);

            for (const ss of rs.scopeSpans ?? []) {
                for (const s of ss.spans ?? []) {
                    total++;
                    // `chat gpt-5` and `execute_tool bash` share a shape; group
                    // by the leading verb so the list stays readable.
                    const name = s.name.split(" ")[0];
                    if (!spans.has(name)) spans.set(name, { count: 0, attrs: new Set() });
                    const e = spans.get(name);
                    e.count++;
                    for (const a of s.attributes ?? []) e.attrs.add(a.key);
                }
            }
        }
    }

    if (!total) {
        console.log(`No traces in ${path}\n`);
        return;
    }

    console.log(`Traces — ${total} spans in ${path}\n`);
    console.log("Resource attribute sets (one per emitting client):");
    for (const [key, count] of [...resources].sort((a, b) => b[1] - a[1])) {
        console.log(`  ${count.toString().padStart(4)}x  ${key}`);
    }
    console.log("");
    console.log("Span names:");
    for (const [name, e] of [...spans].sort((a, b) => b[1].count - a[1].count)) {
        console.log(`  ${e.count.toString().padStart(5)}  ${name}`);
        if (e.attrs.size) console.log(`         attrs: ${[...e.attrs].sort().join(", ")}`);
    }
    console.log("");
}

function summarizeMetrics(path) {
    const metrics = new Map();

    for (const batch of batches(path)) {
        for (const rm of batch.resourceMetrics ?? []) {
            for (const sm of rm.scopeMetrics ?? []) {
                for (const m of sm.metrics ?? []) {
                    const kind = m.histogram
                        ? "histogram"
                        : m.sum
                          ? "sum"
                          : m.gauge
                            ? "gauge"
                            : "unknown";
                    if (!metrics.has(m.name)) {
                        metrics.set(m.name, { kind, unit: m.unit ?? "-", labels: new Set() });
                    }
                    const e = metrics.get(m.name);
                    const points = (m.histogram ?? m.sum ?? m.gauge)?.dataPoints ?? [];
                    for (const p of points) {
                        for (const a of p.attributes ?? []) e.labels.add(a.key);
                    }
                }
            }
        }
    }

    if (!metrics.size) {
        console.log(`No metrics in ${path}\n`);
        return;
    }

    console.log(`Metrics — ${metrics.size} instruments in ${path}\n`);
    for (const [name, e] of [...metrics].sort()) {
        console.log(`  ${name}  (${e.kind}, unit=${e.unit})`);
        console.log(`     labels: ${[...e.labels].sort().join(", ") || "(none)"}`);
    }
    console.log("");
}

summarizeTraces(traceFile);
summarizeMetrics(metricFile);
