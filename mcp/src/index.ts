#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { primeContext, explainContext, renderManifest, type InjectMode } from "./inject.js";
import { loadPsyche } from "./psyche.js";
import { retrieveContext, formatContext } from "./gbrain.js";
import { validateConfig, renderHealthReport } from "./health.js";

const server = new Server(
  { name: "glia-context", version: "0.1.0" },
  {
    capabilities: { tools: {} },
    // Sent to the client at initialize — nudges compliant agents to prime first.
    instructions:
      "This server primes you with WHO THE USER IS (their psyche/identity map) plus " +
      "WHAT'S RELEVANT to their task, from their gbrain. At the START of a substantive " +
      "session — before answering a request that benefits from knowing them — call " +
      "`prime_context` with what the user is trying to do, and reason from what it returns " +
      "so your answer serves this specific person, not a generic user. Use `who_am_i` for " +
      "identity alone, `recall` for pure retrieval, and `health` to check configuration.",
  },
);

const TOOLS = [
  {
    name: "prime_context",
    description:
      "Prime this session with WHO THE USER IS (their psyche/identity map) and WHAT'S RELEVANT to the task (retrieved from their gbrain). Call this FIRST, before answering a substantive request, so your answer serves this specific person — their values, worldview, and how they work — not a generic user. Returns a context block to fold into your reasoning.",
    inputSchema: {
      type: "object",
      properties: {
        task: {
          type: "string",
          description: "What the user is trying to do this session (their prompt/goal).",
        },
        mode: {
          type: "string",
          enum: ["psyche", "context", "both"],
          description:
            "psyche = who they are only; context = relevant retrieval only; both = identity front-loaded, then relevance (default).",
        },
        maxTokens: {
          type: "number",
          description: "Approx token budget for the injection (default 60000).",
        },
      },
      required: ["task"],
    },
  },
  {
    name: "who_am_i",
    description:
      "Return the user's psyche/identity map — who they are, their values, worldview, and essays — independent of any task. Use to prime yourself with the person you're working for.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "recall",
    description:
      "Retrieve pages relevant to a query from the user's gbrain knowledge base (pure relevance, no identity). Use when you need specific facts/context the user has recorded.",
    inputSchema: {
      type: "object",
      properties: { query: { type: "string" } },
      required: ["query"],
    },
  },
  {
    name: "health",
    description:
      "Report glia-context configuration health: whether the psyche map, gbrain command, and source dir are reachable, and whether identity/retrieval will work. Pass probe=true to run a live retrieval round-trip.",
    inputSchema: {
      type: "object",
      properties: {
        probe: { type: "boolean", description: "Run a live gbrain query to confirm retrieval end-to-end." },
      },
    },
  },
  {
    name: "explain_context",
    description:
      "Preview EXACTLY what prime_context would inject for a task — the identity source + which page sections, the pages retrieval would add (with scores), and token estimates — WITHOUT the full content. Use to see/trust what's loaded before priming, or to decide whether priming is worth it.",
    inputSchema: {
      type: "object",
      properties: {
        task: { type: "string", description: "The task you'd prime for." },
        mode: { type: "string", enum: ["psyche", "context", "both"] },
        maxTokens: { type: "number", description: "Token budget to preview against (default 60000) — must match your prime_context call to be accurate." },
      },
      required: ["task"],
    },
  },
];

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args } = req.params;
  try {
    if (name === "prime_context") {
      const r = await primeContext(String(args?.task ?? ""), {
        mode: args?.mode as InjectMode | undefined,
        maxTokens: typeof args?.maxTokens === "number" ? args.maxTokens : undefined,
      });
      return {
        content: [
          {
            type: "text",
            text:
              `<!-- glia-context: mode=${r.mode}, ~${r.tokens} tokens ` +
              `(psyche ~${r.psycheTokens}, context ~${r.contextTokens} from ${r.contextPages} pages), ` +
              `psyche=${r.psycheStatus}, retrieval=${r.retrievalStatus}, degraded=${r.degraded}, ` +
              `source=${r.source} -->\n\n${r.text}`,
          },
        ],
      };
    }
    if (name === "who_am_i") {
      const p = await loadPsyche();
      const text = p.status === "empty"
        ? "> glia-context status: DEGRADED\n> identity: UNAVAILABLE — no psyche file and no readable gbrain source."
        : p.text;
      return { content: [{ type: "text", text }] };
    }
    if (name === "recall") {
      const r = await retrieveContext(String(args?.query ?? ""));
      const body = formatContext(r.pages) || "No relevant pages found.";
      const status = r.status === "ok"
        ? `${r.pages.length} pages${r.cached ? ", cached" : ""}, ${r.elapsedMs}ms`
        : `${r.status}${r.detail ? ": " + r.detail : ""}`;
      return {
        content: [{ type: "text", text: `> glia-context recall: ${status}\n\n${body}` }],
      };
    }
    if (name === "explain_context") {
      const m = await explainContext(String(args?.task ?? ""), {
        mode: args?.mode as InjectMode | undefined,
        maxTokens: typeof args?.maxTokens === "number" ? args.maxTokens : undefined,
      });
      return { content: [{ type: "text", text: renderManifest(m) }] };
    }
    if (name === "health") {
      const report = validateConfig(true);
      let probe = "";
      if (args?.probe === true) {
        const r = await retrieveContext("glia self test");
        probe = `\nlive probe: retrieval=${r.status} (${r.pages.length} pages, ${r.elapsedMs}ms${r.cached ? ", cached" : ""})${r.detail ? " — " + r.detail : ""}`;
      }
      return { content: [{ type: "text", text: renderHealthReport(report) + probe }], isError: report.overall === "fail" };
    }
    return { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true };
  } catch (e: any) {
    return { content: [{ type: "text", text: `Error: ${e?.message ?? e}` }], isError: true };
  }
});

// CLI one-shot modes (no server): handy for a quick terminal check, scripting,
// or the app — `node dist/index.js --explain "<task>"` prints the injection
// manifest; `--prime "<task>"` prints the full prime; `--health` the report.
{
  const argv = process.argv;
  const flag = (name: string) => { const i = argv.indexOf(name); return i !== -1 ? (argv[i + 1] ?? "") : null; };
  const explain = flag("--explain");
  const prime = flag("--prime");
  if (explain !== null) { console.log(renderManifest(await explainContext(explain))); process.exit(0); }
  if (prime !== null) { console.log((await primeContext(prime)).text); process.exit(0); }
  if (argv.includes("--health")) { console.log(renderHealthReport(validateConfig(true))); process.exit(0); }
}

// Validate configuration at startup: log the health report to stderr (stdout is
// the JSON-RPC channel), and exit only when nothing is usable (or strict mode).
const report = validateConfig();
console.error(renderHealthReport(report));
if (report.exitWorthy) {
  console.error("glia-context: fatal configuration error — exiting. See report above.");
  process.exit(1);
}

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("glia-context MCP server running on stdio");
