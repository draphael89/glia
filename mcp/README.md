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
core** (capped) and hands the larger share of the budget to retrieval, so the
answer stays grounded. The cap is measured, not guessed: a
[dose-response run](../experiments/psyche-injection/REPORT-v5.md) found a
~3k-token core (self-page + top essays, front-loaded) reaches ~95% of the full
psyche's blind ranking — though the very deepest *insight* keeps climbing with
more identity, so the 40% cap is set to clear that knee comfortably at every
budget while still leaving the majority of the window for retrieval.

**Retrieval is deduped against the psyche.** On identity-shaped tasks ~50% of the
top gbrain hits are pages *already in the psyche* (your starred essays) —
re-injecting them wastes budget on content the model already has. So in `both`
mode, retrieval drops pages present in the injected psyche and **backfills** down
the ranked list to `topK` genuinely-new unique pages. And what actually happens
is always reported: `prime_context` prepends a `> glia-context status: OK|DEGRADED`
line naming the identity source and retrieval outcome (never silently empty).

## Tools

| Tool | What it does |
|---|---|
| `prime_context` | The headline. Given the session's task, returns a context block: a concentrated **who you are** core + **relevant, deduped gbrain pages**. `mode`: `psyche` / `context` / `both` (default — the recipe v2 proved). Call it first. |
| `who_am_i` | Just the psyche map — who you are, values, essays. |
| `recall` | Pure relevance retrieval from gbrain for a query. |
| `explain_context` | Preview *exactly* what `prime_context` would inject — identity sections + retrieved page slugs + token estimates — **without** the full content. See and trust what's loaded. |
| `health` | Config health: are the psyche, gbrain command, and source reachable? `probe=true` runs a live retrieval round-trip. |

The server also sends MCP `instructions` at initialize, nudging compliant clients
to call `prime_context` at the start of a substantive session.

**CLI (no client needed)** — inspect the injection from a terminal or a script:

```bash
node dist/index.js --explain "plan the launch"   # preview the manifest
node dist/index.js --prime   "plan the launch"   # the full prime text
node dist/index.js --health                       # config health report
```

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
