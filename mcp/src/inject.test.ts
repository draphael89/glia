import { test } from "node:test";
import assert from "node:assert/strict";
import { estimateTokens, truncateToTokens } from "./config.js";
import { cleanBody, identityRank } from "./psyche.js";
import { primeContext } from "./inject.js";

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
});

test("primeContext both mode budgets psyche first (identity survives)", async () => {
  const r = await primeContext("plan my quarter", { mode: "both", maxTokens: 3000 });
  assert.equal(r.mode, "both");
  assert.ok(r.psycheTokens > 0);
  // total stays within a reasonable multiple of the budget
  assert.ok(r.tokens <= 3000 * 1.5);
});
