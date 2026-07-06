import { test } from "node:test";
import assert from "node:assert/strict";
import { estimateTokens, truncateToTokens, config } from "./config.js";
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

test("truncateToTokens returns nothing for a non-positive budget (never the whole text)", () => {
  const text = "para one\n\npara two\n\npara three that is quite a bit longer than the rest";
  assert.equal(truncateToTokens(text, 0), "");
  assert.equal(truncateToTokens(text, -1000), "");
});

test("out-of-enum mode coerces to both, not a falsely-OK empty prime", async () => {
  _clearRetrievalCache();
  const r = await primeContext("anything", { mode: "identity" as any, maxTokens: 60000 });
  assert.equal(r.mode, "both", "invalid mode falls back to both");
  assert.ok(r.psycheTokens > 0, "identity is still injected (not an empty prime)");
  assert.ok(r.contextPages > 0, "retrieval is still injected");
  _clearRetrievalCache();
});

test("non-positive maxTokens keeps the psyche capped, doesn't dump the whole file", async () => {
  const r = await primeContext("anything", { mode: "psyche", maxTokens: -1000 });
  // budget coerced to the 60k default → psyche mode injects up to the file, but the
  // point is it's bounded/non-degenerate, not the truncate-bug's whole-2MB leak.
  assert.ok(r.psycheTokens > 0 && r.psycheTokens < 1_000_000, "psyche tokens are bounded");
  assert.equal(r.mode, "psyche");
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

test("relevance floor anchors to the first READABLE page, not an unreadable top-ranked one", async () => {
  // regression: floor was candidates[0].score * frac; if the top page is missing/
  // unreadable, that poisoned the floor and cut the real best readable page.
  const savedCmd = config.gbrainCmd, savedFloor = config.gbrainRelScoreFloor;
  config.gbrainCmd = "test-fixtures/gbrain-stub-missing-top.sh";  // top=0.99 (missing), then note-beta=0.40
  config.gbrainRelScoreFloor = 0.5;   // 0.99*0.5=0.495 > 0.40 → old code would drop note-beta
  _clearRetrievalCache();
  try {
    const r = await retrieveContext("anything");
    assert.equal(r.pages.length, 1, "the readable lower page must survive the unreadable top");
    assert.equal(r.pages[0].slug, "note-beta");
  } finally {
    config.gbrainCmd = savedCmd;
    config.gbrainRelScoreFloor = savedFloor;
    _clearRetrievalCache();
  }
});

test("retrieval drops operational snapshot/provenance dumps", async () => {
  const savedCmd = config.gbrainCmd;
  config.gbrainCmd = "test-fixtures/gbrain-stub-noise.sh";  // top hit is a snapshots/ dump
  _clearRetrievalCache();
  try {
    const r = await retrieveContext("anything");
    assert.ok(!r.pages.some((p) => /snapshots\//.test(p.slug)), "snapshot dumps must be filtered out");
    assert.ok(r.pages.some((p) => p.slug === "note-beta"), "the substantive page survives");
  } finally {
    config.gbrainCmd = savedCmd;
    _clearRetrievalCache();
  }
});

test("gbrain-get fallback recovers a top page missing from the mirror", async () => {
  // The query returns live-only-page (absent from the fixture mirror); the fallback
  // reads it live via `gbrain get`, so retrieval isn't silently empty.
  const savedCmd = config.gbrainCmd;
  config.gbrainCmd = "test-fixtures/gbrain-stub-fallback.sh";
  _clearRetrievalCache();
  try {
    const r = await retrieveContext("anything");
    assert.equal(r.pages.length, 1, "the mirror-missing top page must be recovered via get");
    assert.equal(r.pages[0].slug, "live-only-page");
    assert.match(r.pages[0].body, /Live-fetched/);
  } finally {
    config.gbrainCmd = savedCmd;
    _clearRetrievalCache();
  }
});

test("parallel fallback recovers MULTIPLE mirror-missing pages (up to the cap)", async () => {
  // The prefetch refactor's whole point: several top pages absent from the mirror are
  // fetched CONCURRENTLY, not one-per-page in series. All three must come back, in order.
  const savedCmd = config.gbrainCmd;
  config.gbrainCmd = "test-fixtures/gbrain-stub-multi-miss.sh";
  _clearRetrievalCache();
  try {
    const r = await retrieveContext("anything");
    assert.equal(r.pages.length, 3, "all three mirror-missing pages recovered via parallel get");
    assert.deepEqual(r.pages.map((p) => p.slug), ["miss-one", "miss-two", "miss-three"]);
    assert.match(r.pages[0].body, /first live-only/);
    assert.match(r.pages[2].body, /third live-only/);
  } finally {
    config.gbrainCmd = savedCmd;
    _clearRetrievalCache();
  }
});

test("fallback cap of 0 disables live-read recovery entirely", async () => {
  // GBRAIN_GET_FALLBACK_MAX=0 must skip the prefetch and every fallback, so an
  // all-miss query returns empty rather than silently spawning gbrain get.
  const savedCmd = config.gbrainCmd;
  const savedMax = config.gbrainGetFallbackMax;
  config.gbrainCmd = "test-fixtures/gbrain-stub-multi-miss.sh";
  config.gbrainGetFallbackMax = 0;
  _clearRetrievalCache();
  try {
    const r = await retrieveContext("anything");
    assert.equal(r.pages.length, 0, "cap=0 recovers nothing (all pages miss the mirror)");
    assert.equal(r.status, "empty");
  } finally {
    config.gbrainCmd = savedCmd;
    config.gbrainGetFallbackMax = savedMax;
    _clearRetrievalCache();
  }
});

test("fallback cap bounds how many mirror-missing pages are recovered", async () => {
  // With the cap at 2, only the top two misses are fetched; the third is dropped —
  // the loop's fallbackUsed guard and the prefetch window must agree on the bound.
  const savedCmd = config.gbrainCmd;
  const savedMax = config.gbrainGetFallbackMax;
  config.gbrainCmd = "test-fixtures/gbrain-stub-multi-miss.sh";
  config.gbrainGetFallbackMax = 2;
  _clearRetrievalCache();
  try {
    const r = await retrieveContext("anything");
    assert.equal(r.pages.length, 2, "cap=2 recovers exactly the top two misses");
    assert.deepEqual(r.pages.map((p) => p.slug), ["miss-one", "miss-two"]);
  } finally {
    config.gbrainCmd = savedCmd;
    config.gbrainGetFallbackMax = savedMax;
    _clearRetrievalCache();
  }
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
