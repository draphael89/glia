# PR draft — awaiting David's go-ahead before anything is pushed/opened

**Target:** garrytan/gbrain ← draphael89/gbrain:glia/export-graph
**Branch commit:** b330f5d (worktree: /tmp/glia-export-graph)
**Status:** NOT pushed, NOT opened. Fork was declined; this is the ready-to-go draft.

---

## Title
feat(export-graph): read-scope `export_graph` op for external graph visualizers

## Body

Adds a contract-first `export_graph` read operation that returns the page/link
graph as JSON, for external tools that want to visualize or sync a brain
without coupling to internal schema.

**Motivation.** Building a native macOS viewer (Glia) surfaced the need for a
stable, engine-agnostic way to pull the whole graph. Reading `pages`/`links`
directly couples a client to schema that changes across migrations and doesn't
exist on PGLite the same way. A contract op is the durable seam.

**What it does.**
- New op `export_graph`, `scope: 'read'`, works identically on postgres + pglite
- Params: `source_id?` (respects `sourceScopeOpts` isolation; narrows, never
  widens), `updated_after?` (ISO cursor for delta fetch), `include_deleted?`
- Returns `{ generated_at, nodes: [{id, slug, type, source, title, created,
  updated}], links: [{source, target, type}] }`; links only between
  non-deleted, in-scope pages; `SELECT DISTINCT` collapses provenance dupes;
  deterministic ordering
- Exposed in CLI via existing contract-generation; appears in `--tools-json`

**Testing.**
- `test/export-graph.test.ts`: 18/18 (scope precedence, soft-delete, delta
  cursor incl. µs-exact strict-`>`, edge dedup, wire shape, title truncation,
  auth narrowing, permission_denied, invalid_params)
- `test/e2e/engine-parity.test.ts`: +1 parity case, passes on ephemeral
  Dockerized postgres (pgvector:pg16) AND pglite
- `bun run typecheck` clean; CI gate scripts pass

No VERSION/CHANGELOG bump (ship-time concern). No docs/KEY_FILES churn.

---

## To ship this (when you decide):
1. `gh repo fork garrytan/gbrain --clone=false`
2. `cd /tmp/glia-export-graph && git remote add fork https://github.com/draphael89/gbrain && git push fork glia/export-graph`
3. `gh pr create --repo garrytan/gbrain --head draphael89:glia/export-graph --title "..." --body-file this`
