# glia-context — the mind-injection MCP server

Primes any MCP-capable agent with **who you are** (your psyche) *and* **what's
relevant** (retrieved from your [gbrain](https://github.com/garrytan/gbrain)) —
at the start of a session, so the model works for *you specifically*, not a
generic user.

This is the operational layer behind [Glia](../). Glia is where you *see and
curate* your mind; `glia-context` is where that map gets *injected* into an
agent's context. The split is deliberate: Glia exports, this injects.

## Why (the thesis, now measured)

gbrain is great at **relevance retrieval** — the pages that bear on your
question. This server adds a distinct lever: **identity injection** — a map of
who you are, independent of the question. A [blind-judged experiment](../experiments/psyche-injection)
found identity injection beats relevance retrieval and wins on *insight*, not
just personal fit — and that identity is the high-density signal (piling on
naive retrieval can dilute it). So `prime_context` front-loads the psyche and
budgets it first: if the window is tight, who-you-are survives.

## Tools

| Tool | What it does |
|---|---|
| `prime_context` | The headline. Given the session's task, returns a context block: **who you are** (front-loaded) + **relevant gbrain pages**. `mode`: `psyche` / `context` / `both` (default). Call it first. |
| `who_am_i` | Just the psyche map — who you are, values, essays. |
| `recall` | Pure relevance retrieval from gbrain for a query. |

## Setup

```bash
cd mcp && npm install && npm run build
```

Register with an MCP client (e.g. Claude Code) — add to your MCP config:

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
