// End-to-end: speak MCP JSON-RPC to the built server over stdio, exactly as a
// real client (Claude Code, etc.) would. Three scenarios, all hermetic (fixture
// env — no dependency on a real gbrain/brain):
//   1. happy       — identity + retrieval both work; status OK, nothing degraded
//   2. degraded    — identity OK but gbrain missing; server stays up, reports DEGRADED
//   3. fatal-exit  — nothing usable; server exits 1 with a stderr report
import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const MCP = dirname(fileURLToPath(import.meta.url));
const SERVER = join(MCP, "dist", "index.js");
const FIX = join(MCP, "test-fixtures");
const PSYCHE = join(FIX, "psyche.md");
const SOURCE = join(FIX, "gbrain-source");
const STUB = join(FIX, "gbrain-stub.sh");

let failed = false;
const ok = (c, m) => { console.log((c ? "✓" : "✗") + " " + m); if (!c) failed = true; };

/** Spawn a server with the given env overrides; returns an rpc() + close(). */
function openServer(env) {
  const proc = spawn("node", [SERVER], { cwd: MCP, stdio: ["pipe", "pipe", "inherit"], env: { ...process.env, ...env } });
  let buf = "";
  const pending = new Map();
  proc.stdout.on("data", (d) => {
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
  const rpc = (method, params) => new Promise((res, rej) => {
    const id = Math.floor(performance.now() * 1000) % 1e9;
    pending.set(id, res);
    proc.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    setTimeout(() => { if (pending.has(id)) { pending.delete(id); rej(new Error(`rpc ${method} timed out`)); } }, 15000);
  });
  return { proc, rpc, close: () => proc.kill() };
}

const call = (s, name, args = {}) => s.rpc("tools/call", { name, arguments: args })
  .then((r) => r.result?.content?.[0]?.text ?? "");

// ── Scenario 1: happy path ──────────────────────────────────────────────────
{
  const s = openServer({ GLIA_PSYCHE: PSYCHE, GBRAIN_SOURCE_DIR: SOURCE, GBRAIN_CMD: STUB });
  const init = await s.rpc("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "e2e", version: "1" } });
  ok(init.result?.serverInfo?.name === "glia-context", "[happy] initialize → glia-context");

  const list = await s.rpc("tools/list", {});
  const names = (list.result?.tools ?? []).map((t) => t.name);
  ok(["prime_context", "who_am_i", "recall", "health"].every((n) => names.includes(n)), `[happy] lists all tools (${names.join(",")})`);

  const who = await call(s, "who_am_i");
  ok(who.includes("FIXTURE-PSYCHE-MARKER"), "[happy] who_am_i returns the canonical psyche");

  const prime = await call(s, "prime_context", { task: "hermes architecture", mode: "both" });
  ok(prime.includes("> glia-context status: OK"), "[happy] prime_context reports status OK");
  ok(!prime.includes("DEGRADED"), "[happy] prime_context not degraded");
  ok(prime.includes("## Who I am") && prime.includes("FIXTURE-PSYCHE-MARKER"), "[happy] prime_context includes identity");
  ok(prime.includes("## Relevant context") && prime.includes("FIXTURE-ALPHA-MARKER"), "[happy] prime_context includes retrieval");
  ok(/retrieval=ok/.test(prime), "[happy] prime_context metadata retrieval=ok");

  const health = await call(s, "health");
  ok(/overall: OK/.test(health) && /identity: available/.test(health) && /retrieval: available/.test(health), "[happy] health reports all available");

  const recall = await call(s, "recall", { query: "gbrain sync" });
  ok(recall.includes("> glia-context recall:") && recall.includes("FIXTURE-ALPHA-MARKER"), "[happy] recall returns pages + status");

  s.close();
}

// ── Scenario 2: running-degraded (identity OK, gbrain missing) ──────────────
{
  const s = openServer({ GLIA_PSYCHE: PSYCHE, GBRAIN_SOURCE_DIR: SOURCE, GBRAIN_CMD: "/nonexistent/gbrain" });
  const init = await s.rpc("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "e2e", version: "1" } });
  ok(init.result?.serverInfo?.name === "glia-context", "[degraded] server stays UP with retrieval dead");

  const prime = await call(s, "prime_context", { task: "plan the quarter", mode: "both" });
  ok(prime.includes("> glia-context status: DEGRADED"), "[degraded] prime_context reports DEGRADED");
  ok(/retrieval: DISABLED/.test(prime), "[degraded] prime_context names the disabled retrieval");
  ok(prime.includes("FIXTURE-PSYCHE-MARKER"), "[degraded] identity still injected despite dead retrieval");

  const recall = await call(s, "recall", { query: "anything" });
  ok(/disabled/.test(recall), "[degraded] recall reports disabled, doesn't crash");

  s.close();
}

// ── Scenario 3: fatal-exit (nothing usable) ─────────────────────────────────
{
  const code = await new Promise((res) => {
    const p = spawn("node", [SERVER], {
      cwd: MCP, stdio: ["pipe", "pipe", "inherit"],
      env: { ...process.env, GLIA_PSYCHE: "/nonexistent/p.md", GBRAIN_SOURCE_DIR: "/nonexistent/src", GBRAIN_CMD: "/nonexistent/gbrain" },
    });
    p.on("exit", (c) => res(c));
    setTimeout(() => { p.kill(); res("timeout"); }, 8000);
  });
  ok(code === 1, `[fatal] server exits 1 when nothing is usable (got ${code})`);
}

console.log(failed ? "\nE2E FAILED" : "\nE2E PASSED");
process.exit(failed ? 1 : 0);
