// End-to-end: speak MCP JSON-RPC to the built server over stdio, exactly as a
// real client (Claude Code, etc.) would. Verifies initialize → list → call.
import { spawn } from "node:child_process";

const srv = spawn("node", ["dist/index.js"], { stdio: ["pipe", "pipe", "inherit"] });
let buf = "";
const pending = new Map();

srv.stdout.on("data", (d) => {
  buf += d.toString();
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    const msg = JSON.parse(line);
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  }
});

function rpc(method, params) {
  const id = Math.floor(performance.now() * 1000) % 1e9;
  return new Promise((res) => {
    pending.set(id, res);
    srv.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  });
}

let failed = false;
const ok = (c, m) => { console.log((c ? "✓" : "✗") + " " + m); if (!c) failed = true; };

const init = await rpc("initialize", {
  protocolVersion: "2024-11-05",
  capabilities: {},
  clientInfo: { name: "e2e", version: "1" },
});
ok(init.result?.serverInfo?.name === "glia-context", "initialize → glia-context");

const list = await rpc("tools/list", {});
const names = (list.result?.tools ?? []).map((t) => t.name);
ok(names.includes("prime_context"), "lists prime_context");
ok(names.includes("who_am_i"), "lists who_am_i");
ok(names.includes("recall"), "lists recall");

const who = await rpc("tools/call", { name: "who_am_i", arguments: {} });
const whoText = who.result?.content?.[0]?.text ?? "";
ok(whoText.length > 1000, `who_am_i returns psyche (${whoText.length} chars)`);
ok(/david/i.test(whoText), "who_am_i psyche mentions the user");

const prime = await rpc("tools/call", {
  name: "prime_context",
  arguments: { task: "Should I ship Glia or deepen the system?", mode: "both", maxTokens: 8000 },
});
const primeText = prime.result?.content?.[0]?.text ?? "";
ok(primeText.includes("Who I am"), "prime_context includes identity");
ok(/mode=both/.test(primeText), "prime_context reports mode metadata");

const recall = await rpc("tools/call", { name: "recall", arguments: { query: "hermes architecture" } });
const recallText = recall.result?.content?.[0]?.text ?? "";
ok(recallText.length > 0, `recall returns pages (${recallText.length} chars)`);

srv.kill();
console.log(failed ? "\nE2E FAILED" : "\nE2E PASSED");
process.exit(failed ? 1 : 0);
