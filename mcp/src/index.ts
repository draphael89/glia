#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { primeContext, type InjectMode } from "./inject.js";
import { loadPsyche } from "./psyche.js";
import { retrieveContext, formatContext } from "./gbrain.js";
import { validateConfig, renderHealthReport } from "./health.js";

const server = new Server(
  { name: "glia-context", version: "0.1.0" },
  { capabilities: { tools: {} } },
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
