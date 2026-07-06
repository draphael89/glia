#!/usr/bin/env node
// v17 — capture full-retrieval (cap-8) context + both injections for FRESH tasks,
// pre-classified GENERATIVE (answer synthesized from who David is) vs DIAGNOSTIC
// (answer is the retrieved facts). Tests whether v16's task-shape finding replicates:
// generative tasks should favor `both`, diagnostic should favor `context`.
// Writes materials/{id}-context-full.md + {id}-both-full.md (gitignored).
import { primeContext } from "../../../mcp/dist/inject.js";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const base = join(dirname(fileURLToPath(import.meta.url)), "..");

// GENERATIVE — the quality hinges on knowing David's values / voice / worldview.
// DIAGNOSTIC — the quality hinges on the retrieved facts, not who he is.
export const TASKS = [
  { id: "g1", type: "generative", prompt: "Write my one-sentence personal mission statement, in my own voice — something true to what I'm actually about." },
  { id: "g2", type: "generative", prompt: "Draft the opening 3 sentences of a talk I'd give about what I'm building and why it matters to me." },
  { id: "g3", type: "generative", prompt: "Design the shape of my ideal working day — a structure that fits how I actually operate and what I value, not a generic productivity template." },
  { id: "g4", type: "generative", prompt: "Write me a short personal manifesto (3–4 sentences) I could pin above my desk to keep me pointed at what matters." },
  { id: "d1", type: "diagnostic", prompt: "What did we decide about the NIL product MVP — the contracts, asset generation, and monitoring? Just the decisions." },
  { id: "d2", type: "diagnostic", prompt: "Summarize the key points from my recent meetings about the creative pipeline and performance review." },
  { id: "d3", type: "diagnostic", prompt: "What are the open questions or product risks around the Reflections knowledge graph, per my notes?" },
  { id: "d4", type: "diagnostic", prompt: "According to my notes, how should deterministic gates and AI judgment divide the work in a recommendation system? Give me the recorded reasoning." },
];

const out = [];
for (const t of TASKS) {
  for (const mode of ["context", "both"]) {
    const r = await primeContext(t.prompt, { mode });
    writeFileSync(join(base, `materials/${t.id}-${mode}-full.md`), r.text);
    process.stderr.write(`  ${t.id}/${mode}: ${r.tokens} tok, ${r.contextPages} pages\n`);
  }
  out.push({ id: t.id, type: t.type, prompt: t.prompt });
}
writeFileSync(join(base, "materials/v17-tasks.json"), JSON.stringify(out, null, 2));
process.stderr.write(`\nwrote ${out.length} tasks × 2 modes + v17-tasks.json\n`);
