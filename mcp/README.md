# glia-context — the mind-injection MCP server

Primes any MCP-capable agent with **who you are** (your psyche) *and* **what's
relevant** (retrieved from your [gbrain](https://github.com/garrytan/gbrain)) —
at the start of a session, so the model works for *you specifically*, not a
generic user.

This is the operational layer behind [Glia](../). Glia is where you *see and
curate* your mind; `glia-context` is where that map gets *injected* into an
agent's context. The split is deliberate: Glia exports, this injects.

## Why (the thesis, measured — and corrected)

gbrain is great at **relevance retrieval** — the pages that bear on your
question. This server adds a distinct lever: **identity injection** — a map of
who you are, independent of the question.

A [blind-judged experiment](../experiments/psyche-injection) tested it, then
tried to break its own result. The honest finding (v2): identity is a real
signal, but a **complement** to relevance, not a replacement. Injecting *both*
wins — the combination beats relevance-alone 71% of the time under judges blind
to the psyche. The mechanism is clean: **retrieval buys specificity and
actionability; identity buys insight**. And on neutral technical tasks all arms
tie — identity helps *specifically* on tasks that are about you, it isn't a
global "try harder" effect. (An earlier non-blind run overclaimed that psyche
*alone* dominates and retrieval *dilutes* it; that didn't survive blind judging.
See [FINDINGS.md](../experiments/psyche-injection/FINDINGS.md).)

So `prime_context` defaults to `both`: it front-loads a **concentrated identity
core** (capped — identity is high-density, a small dose carries the insight
lift) and hands the larger share of the budget to retrieval, so the answer
stays grounded.

## Tools

| Tool | What it does |
|---|---|
| `prime_context` | The headline. Given the session's task, returns a context block: a concentrated **who you are** core + **relevant gbrain pages**. `mode`: `psyche` / `context` / `both` (default — the recipe v2 proved). Call it first. |
| `who_am_i` | Just the psyche map — who you are, values, essays. |
| `recall` | Pure relevance retrieval from gbrain for a query. |

## Setup

One command — builds and registers with Claude Code:

```bash
cd mcp && ./install.sh
```

Or manually:

```bash
cd mcp && npm install && npm run build
claude mcp add glia-context node "$(pwd)/dist/index.js"     # Claude Code
```

For **Hermes** or any other MCP client, add a stdio server pointing at the
built entrypoint:

```json
{
  "mcpServers": {
    "glia-context": { "command": "node", "args": ["/absolute/path/to/glia/mcp/dist/index.js"] }
  }
}
```

Then, at the start of a session: *"prime_context with what I'm trying to do."*

## Configuration (env)

| Var | Default | Meaning |
|---|---|---|
| `GLIA_PSYCHE` | `~/.glia/psyche.md` | Canonical psyche map (Glia writes this). Falls back to building from the gbrain source if absent. |
| `GBRAIN_SOURCE_DIR` | `~/.gbrain/source-default` | Markdown mirror — page reads + fallback psyche. |
| `GBRAIN_CMD` | `~/.hermes/scripts/gbrain-local.sh` | Command for `gbrain query`. Set to `gbrain` for a standard install. |

## Tests

```bash
npm run build && node --test dist/inject.test.js   # unit
node test-e2e.mjs                                   # full MCP JSON-RPC round-trip
```
