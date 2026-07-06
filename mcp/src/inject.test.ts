import { test } from "node:test";
import assert from "node:assert/strict";
import { estimateTokens, truncateToTokens } from "./config.js";
import { cleanBody, identityRank, buildPsycheFromSource, psycheSlugs } from "./psyche.js";
import { primeContext, explainContext } from "./inject.js";
import { retrieveContext, _clearRetrievalCache, safePagePath } from "./gbrain.js";

// Tests run hermetically via the `test` npm script env:
//   GLIA_PSYCHE=test-fixtures/psyche.md
//   GBRAIN_SOURCE_DIR=test-fixtures/gbrain-source
//   GBRAIN_CMD=test-fixtures/gbrain-stub.sh  (returns note-alpha, note-beta)

test("token estimate ~4 chars/token", () => {
  assert.equal(estimateTokens("x".repeat(400)), 100);
});

test("truncateToTokens caps length and marks truncation", () => {
  const long = "para one.\n\n" + "y".repeat(10_000);
  const out = truncateToTokens(long, 50); // ~200 chars
  assert.ok(out.length < 400);
  assert.ok(out.includes("truncated"));
});

test("cleanBody strips frontmatter and fact markers", () => {
  const raw = "---\ntype: note\n---\n<!--- gbrain:facts:begin -->X<!--- gbrain:facts:end -->\n# Body\ntext";
  const c = cleanBody(raw);
  assert.ok(!c.includes("type: note"));
  assert.ok(!c.includes("gbrain:facts"));
  assert.ok(c.includes("# Body"));
});

test("identityRank front-loads self then essays then concepts", () => {
  assert.ok(identityRank("people-david") < identityRank("originals/telos"));
  assert.ok(identityRank("originals/telos") < identityRank("concepts/legibility"));
  assert.ok(identityRank("concepts/legibility") < identityRank("notes/x"));
});

test("primeContext psyche mode returns identity, no context section", async () => {
  const r = await primeContext("who am I", { mode: "psyche", maxTokens: 5000 });
  assert.equal(r.mode, "psyche");
  assert.ok(r.psycheTokens > 0);
  assert.equal(r.contextTokens, 0);
  assert.ok(r.text.includes("Who I am"));
  assert.equal(r.psycheStatus, "file"); // GLIA_PSYCHE fixture present
  assert.equal(r.retrievalStatus, "skipped"); // psyche mode does no retrieval
  assert.ok(r.text.includes("FIXTURE-PSYCHE-MARKER"));
});

test("primeContext both mode budgets psyche first (identity survives)", async () => {
  const r = await primeContext("plan my quarter", { mode: "both", maxTokens: 3000 });
  assert.equal(r.mode, "both");
  assert.ok(r.psycheTokens > 0);
  // total stays within a reasonable multiple of the budget
  assert.ok(r.tokens <= 3000 * 1.5);
});

test("primeContext both mode: retrieval works + reports OK status, not degraded", async () => {
  _clearRetrievalCache();
  const r = await primeContext("hermes architecture", { mode: "both", maxTokens: 60000 });
  assert.equal(r.psycheStatus, "file");
  assert.equal(r.retrievalStatus, "ok");
  assert.equal(r.contextPages, 2); // stub returns note-alpha + note-beta
  assert.equal(r.degraded, false);
  assert.ok(r.text.includes("> glia-context status: OK"));
  assert.ok(r.text.includes("## Relevant context"));
  assert.ok(r.text.includes("FIXTURE-ALPHA-MARKER"));
  // status lines name both components
  assert.ok(r.statusLines.some((l) => l.startsWith("identity:")));
  assert.ok(r.statusLines.some((l) => l.startsWith("retrieval:")));
});

test("retrieval is cached on a repeat query (second call marked cached)", async () => {
  _clearRetrievalCache();
  const a = await primeContext("caching probe query", { mode: "context", maxTokens: 60000 });
  assert.equal(a.retrievalCached, false);
  const b = await primeContext("caching probe query", { mode: "context", maxTokens: 60000 });
  assert.equal(b.retrievalCached, true);
  assert.equal(b.retrievalStatus, "ok");
});

test("buildPsycheFromSource assembles self-page + essays with status 'built'", async () => {
  const p = await buildPsycheFromSource();
  assert.equal(p.status, "built");
  assert.ok(p.text.includes("FIXTURE-SELF-MARKER"));
  assert.ok(p.text.includes("FIXTURE-ORIGINALS-MARKER"));
});

test("psycheSlugs parses the ContextBundle page-header format", () => {
  const text = "## Title\n*person · people-david*\n\nbody\n\n## Other\n*original · originals/telos*\n";
  const s = psycheSlugs(text);
  assert.ok(s.has("people-david"));
  assert.ok(s.has("originals/telos"));
  assert.equal(s.size, 2);
});

test("retrieveContext excludes psyche slugs (dedup) before taking topK", async () => {
  _clearRetrievalCache();
  // stub returns note-alpha + note-beta; excluding note-alpha leaves only note-beta
  const r = await retrieveContext("anything", { excludeSlugs: new Set(["note-alpha"]) });
  assert.equal(r.status, "ok");
  assert.equal(r.pages.length, 1);
  assert.equal(r.pages[0].slug, "note-beta");
  assert.equal(r.dedupedCount, 1);       // note-alpha dropped as already-in-identity
});

test("safePagePath blocks slug path-traversal, allows normal + nested slugs", () => {
  const base = "/brain/source";
  assert.equal(safePagePath(base, "note-alpha"), "/brain/source/note-alpha.md");
  assert.equal(safePagePath(base, "originals/telos"), "/brain/source/originals/telos.md");
  // escapes — must be rejected
  assert.equal(safePagePath(base, "../../../etc/passwd"), null);
  assert.equal(safePagePath(base, "../secret"), null);
  assert.equal(safePagePath(base, "/etc/passwd"), null);
  assert.equal(safePagePath(base, "originals/../../escape"), null);
});

test("dedupedCount surfaces the v7 mechanism: all-overlap retrieval reads 'deduped', not 'empty'", async () => {
  _clearRetrievalCache();
  // exclude BOTH stub pages → retrieval is empty *because* everything is already
  // in the identity (the identity-heavy case), not because gbrain found nothing.
  const r = await retrieveContext("anything", { excludeSlugs: new Set(["note-alpha", "note-beta"]) });
  assert.equal(r.pages.length, 0);
  assert.equal(r.status, "empty");
  assert.equal(r.dedupedCount, 2);       // distinguishes deduped-empty from genuinely-empty
  _clearRetrievalCache();
  const none = await retrieveContext("anything");   // no exclude → nothing deduped
  assert.equal(none.dedupedCount, 0);
});

test("explainContext returns a truthful manifest (sections + retrieved slugs, deduped)", async () => {
  const m = await explainContext("hermes architecture", { mode: "both" });
  assert.equal(m.psycheStatus, "file");
  assert.ok(m.psycheTokens > 0);
  assert.equal(m.retrievalStatus, "ok");
  assert.ok(m.retrievalPages.some((p) => p.slug === "note-alpha"));
  assert.ok(m.totalTokens >= m.psycheTokens);
});

test("priming header is mode-aware — psyche mode doesn't claim 'use both'", async () => {
  const psy = (await primeContext("anything", { mode: "psyche" })).text;
  assert.ok(!/use both/i.test(psy), "psyche mode must not tell the model to 'use both'");
  assert.ok(!/what's relevant/i.test(psy), "psyche mode has no relevance block to reference");
  assert.match(psy, /who I am/i);
  const both = (await primeContext("anything", { mode: "both" })).text;
  assert.match(both, /use both/i, "both mode should reference both blocks");
});

test("identity self-page is recognized in BOTH slug forms (people-david ↔ people/david)", () => {
  // rank 0 = the self-page; both dash and slash forms must qualify so the single
  // most important page dedups + front-loads regardless of how the slug is written
  assert.equal(identityRank("people-david"), 0);
  assert.equal(identityRank("people/david"), 0);
  assert.equal(identityRank("originals/telos"), 1);   // essays rank below self
  assert.equal(identityRank("people/someone-else"), 3);
});

test("psycheSlugs is anchored — no false-positive on prose (review fix #2)", () => {
  // bare "· word *emphasis*" in body prose must NOT be parsed as a page marker
  assert.equal(psycheSlugs("we weigh · design *matters*, judges **blind** ranked").size, 0);
  // the real ContextBundle marker still parses
  const s = psycheSlugs("*person · people-david*\n*original · originals/telos*");
  assert.ok(s.has("people-david") && s.has("originals/telos"));
});

test("built psyche emits parseable slug markers so dedup works in built mode (fix #1)", async () => {
  const p = await buildPsycheFromSource();
  const slugs = psycheSlugs(p.text);
  assert.ok(slugs.has("people-david"), "self-page slug marker present");
  assert.ok(slugs.has("originals/telos"), "essay slug marker present");
});

test("explainContext mirrors primeContext budgeting for any maxTokens (fix #3)", async () => {
  // the manifest must reflect the SAME assembly (psyche cap ≤ 40% of budget)
  const m = await explainContext("hermes", { mode: "both", maxTokens: 400 });
  assert.ok(m.psycheTokens <= 400 * 0.4 + 1, `psyche capped to budget (got ${m.psycheTokens})`);
  assert.ok(m.totalTokens >= m.psycheTokens + m.retrievalTokens, "total includes scaffolding");
});
