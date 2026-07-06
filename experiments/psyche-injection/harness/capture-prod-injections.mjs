#!/usr/bin/env node
// v9 — capture the ACTUAL shipped prime_context output (not a reconstruction) for
// each task in each mode, using the real compiled MCP code with ALL its recent
// improvements (mode-aware header, dedup, relevance floor, capped psyche, natural-
// query retrieval). The v9 experiment then generates answers from THESE real
// injections, closing the experiment<->product gap every prior version left open.
//
// Writes materials/prod-injections.json (gitignored — contains psyche content).
import { primeContext } from "../../../mcp/dist/inject.js";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const base = join(dirname(fileURLToPath(import.meta.url)), "..");

// The v8 tasks — natural, production-realistic identity/decision prompts.
const TASKS = [
  { id: "p1", prompt: "I keep splitting focus between Glia (the open-source brain viewer) and the core Reflections product. Should I fold them into one public narrative, or keep them as two separate things? Decide for me and justify the call in terms of what actually matters to me." },
  { id: "p2", prompt: "Be honest with me: what is the single most likely reason I'll be stuck in roughly the same place six months from now, and what one change would most move that? Answer specifically for me, not in generalities." },
  { id: "p3", prompt: "Draft a 100-word speaker bio for me for an AI conference. It should sound like me and be true to what I'm actually building and why." },
  { id: "p4", prompt: "I want to organize my week around 'velocity toward telos' instead of a flat task list. Give me a concrete weekly structure that fits how I actually operate and what I value." },
  { id: "p5", prompt: "What's the one project or commitment I should drop this quarter to protect what matters most — and why that one?" },
];

const out = [];
for (const t of TASKS) {
  const rec = { id: t.id, prompt: t.prompt, injections: {} };
  for (const mode of ["context", "psyche", "both"]) {
    const r = await primeContext(t.prompt, { mode });
    rec.injections[mode] = { text: r.text, tokens: r.tokens, retrievalPages: r.contextPages, degraded: r.degraded };
    process.stderr.write(`  ${t.id}/${mode}: ${r.tokens} tok, ${r.contextPages} pages${r.degraded ? " (DEGRADED)" : ""}\n`);
  }
  out.push(rec);
}
const dest = join(base, "materials/prod-injections.json");
writeFileSync(dest, JSON.stringify(out, null, 2));
process.stderr.write(`\nwrote ${dest}: ${out.length} tasks x 3 modes\n`);
