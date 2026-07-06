// Golden-snapshot tests: pin the exact injection FORMAT so a drift in the
// prime_context / recall output is a red build, not a silent change. Hermetic
// (fixture psyche + canned gbrain stub). Regenerate with UPDATE_GOLDEN=1.
import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";

const MCP = dirname(fileURLToPath(import.meta.url));
const SERVER = join(MCP, "dist", "index.js");
const FIX = join(MCP, "test-fixtures");
const GOLDEN = join(MCP, "test-golden");
const UPDATE = process.env.UPDATE_GOLDEN === "1";

/** Normalize the non-deterministic bits (timings, token counts, abs paths). */
function normalize(text) {
  return text
    .replaceAll(FIX, "<FIX>")
    .replace(/in \d+ms/g, "in <MS>ms")
    .replace(/, \d+ms/g, ", <MS>ms")
    .replace(/~\d+/g, "~<T>");
}

function openServer(env) {
  const proc = spawn("node", [SERVER], { cwd: MCP, stdio: ["pipe", "pipe", "inherit"], env: { ...process.env, ...env } });
  let buf = ""; const pending = new Map();
  proc.stdout.on("data", (d) => {
    buf += d.toString(); let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
      if (!line) continue;
      const msg = JSON.parse(line);
      if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
    }
  });
  const rpc = (method, params) => new Promise((res, rej) => {
    const id = Math.floor(performance.now() * 1000) % 1e9;
    pending.set(id, res);
    proc.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    setTimeout(() => { if (pending.has(id)) { pending.delete(id); rej(new Error(`${method} timeout`)); } }, 15000);
  });
  return { proc, rpc, close: () => proc.kill() };
}

const call = (s, name, args = {}) => s.rpc("tools/call", { name, arguments: args })
  .then((r) => r.result?.content?.[0]?.text ?? "");

let failed = false;
function check(name, actual) {
  if (!existsSync(GOLDEN)) mkdirSync(GOLDEN, { recursive: true });
  const path = join(GOLDEN, `${name}.md`);
  const norm = normalize(actual);
  if (UPDATE) {
    writeFileSync(path, norm);
    console.log(`↻ wrote golden ${name}.md`);
    return;
  }
  if (!existsSync(path)) { console.log(`✗ ${name}: no golden (run test:update-golden)`); failed = true; return; }
  const want = readFileSync(path, "utf8");
  if (norm === want) { console.log(`✓ ${name} matches golden`); return; }
  failed = true;
  console.log(`✗ ${name} DIFFERS from golden:`);
  const a = norm.split("\n"), b = want.split("\n");
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    if (a[i] !== b[i]) { console.log(`  line ${i + 1}:\n    got:  ${a[i] ?? "<eof>"}\n    want: ${b[i] ?? "<eof>"}`); break; }
  }
}

const s = openServer({ GLIA_PSYCHE: join(FIX, "psyche.md"), GBRAIN_SOURCE_DIR: join(FIX, "gbrain-source"), GBRAIN_CMD: join(FIX, "gbrain-stub.sh") });
await s.rpc("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "golden", version: "1" } });

check("prime_context.both", await call(s, "prime_context", { task: "hermes architecture", mode: "both", maxTokens: 60000 }));
check("prime_context.psyche", await call(s, "prime_context", { task: "who am I", mode: "psyche", maxTokens: 60000 }));
check("recall", await call(s, "recall", { query: "gbrain sync" }));

s.close();
console.log(failed ? "\nGOLDEN FAILED" : "\nGOLDEN PASSED");
process.exit(failed ? 1 : 0);
