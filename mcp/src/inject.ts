import { config, estimateTokens, truncateToTokens } from "./config.js";
import { loadPsyche, psycheSlugs, type PsycheStatus } from "./psyche.js";
import { retrieveContext, formatContext, type RetrievalResult, type RetrievalStatus } from "./gbrain.js";

export type InjectMode = "psyche" | "context" | "both";

export interface PrimeResult {
  text: string;
  mode: InjectMode;
  tokens: number;
  psycheTokens: number;
  contextTokens: number;
  contextPages: number;
  source: string;
  /** Where identity came from, or "skipped" in context-only mode. */
  psycheStatus: PsycheStatus | "skipped";
  retrievalStatus: RetrievalStatus;
  retrievalDetail?: string;
  retrievalMs: number;
  retrievalCached: boolean;
  /** True if any component the caller asked for is missing/failed. */
  degraded: boolean;
  /** Human-readable status lines (also rendered into `text`). */
  statusLines: string[];
}

/** Build the status lines that describe exactly what was (and wasn't) injected.
 *  `injectedPages` is what actually made it into the text (may be < what was
 *  retrieved, if the budget dropped the context block). */
function buildStatusLines(a: {
  mode: InjectMode;
  psycheStatus: PsycheStatus | "skipped";
  psycheSource: string;
  retrieval: RetrievalResult;
  injectedPages: number;
}): string[] {
  const out: string[] = [];
  if (a.psycheStatus === "file") out.push(`identity: loaded from ${a.psycheSource}`);
  else if (a.psycheStatus === "built") out.push(`identity: built from gbrain source (canonical Glia export not found at ${config.psycheFile})`);
  else if (a.psycheStatus === "empty") out.push("identity: UNAVAILABLE — no psyche file and no readable gbrain source; answer will NOT be personalized");
  // "skipped" (context-only mode) → no identity line

  if (a.mode !== "psyche") {
    const r = a.retrieval;
    // Retrieval found pages but the token budget left no room for them.
    if (r.pages.length > 0 && a.injectedPages === 0 && (r.status === "ok" || r.status === "empty")) {
      out.push(`retrieval: ${r.pages.length} pages found but dropped — no token budget left after identity`);
    } else if (r.status === "ok") out.push(`retrieval: ${a.injectedPages} pages in ${r.elapsedMs}ms${r.cached ? " (cached)" : ""}`);
    else if (r.status === "empty") out.push(`retrieval: no relevant pages found (${r.elapsedMs}ms)`);
    else if (r.status === "timeout") out.push(`retrieval: TIMED OUT after ${config.gbrainTimeoutMs}ms — context may be incomplete (${a.injectedPages} partial pages)`);
    else if (r.status === "disabled") out.push(`retrieval: DISABLED — ${r.detail ?? "gbrain not configured"}`);
    else if (r.status === "error") out.push(`retrieval: ERROR — ${r.detail ?? "unknown"} (${a.injectedPages} pages)`);
  }
  return out;
}

const renderStatusBlock = (lines: string[], degraded: boolean) =>
  [`> glia-context status: ${degraded ? "DEGRADED" : "OK"}`, ...lines.map((l) => `> ${l}`), ""].join("\n");

export interface ContextManifest {
  mode: InjectMode;
  psycheStatus: PsycheStatus | "skipped";
  psycheSource: string;
  psycheTokens: number;
  psycheSections: string[];   // page slugs present in the (capped) psyche
  retrievalStatus: RetrievalStatus;
  retrievalPages: { slug: string; score: number }[];
  retrievalTokens: number;
  totalTokens: number;
  degraded: boolean;
}

/**
 * Preview what prime_context WOULD inject for a task — the psyche source +
 * sections, the pages retrieval would add, and token estimates — WITHOUT the
 * full content. For transparency ("what's loaded?") and to decide whether to
 * prime. Same budgeting + dedup as primeContext, so the manifest is truthful.
 */
export async function explainContext(
  task: string,
  opts: { mode?: InjectMode; maxTokens?: number } = {},
): Promise<ContextManifest> {
  const mode = opts.mode ?? "both";
  const budget = opts.maxTokens ?? 60_000;

  let psycheText = "";
  let psycheSource = "";
  let psycheStatus: PsycheStatus | "skipped" = "skipped";
  if (mode === "psyche" || mode === "both") {
    const p = await loadPsyche();
    psycheSource = p.source;
    psycheStatus = p.status;
    const psycheBudget = mode === "psyche" ? budget : Math.floor(budget * 0.4);
    psycheText = p.status === "empty" ? "" : truncateToTokens(p.text, psycheBudget);
  }
  const sections = [...psycheSlugs(psycheText)];

  let retrieval: RetrievalResult = { pages: [], status: "skipped", elapsedMs: 0, cached: false, query: task };
  if (mode === "context" || mode === "both") {
    const exclude = mode === "both" && psycheText ? psycheSlugs(psycheText) : undefined;
    retrieval = await retrieveContext(task, { excludeSlugs: exclude });
  }
  const psycheTokens = estimateTokens(psycheText);
  const retrievalTokens = estimateTokens(formatContext(retrieval.pages));

  return {
    mode, psycheStatus, psycheSource, psycheTokens, psycheSections: sections,
    retrievalStatus: retrieval.status,
    retrievalPages: retrieval.pages.map((p) => ({ slug: p.slug, score: p.score })),
    retrievalTokens,
    totalTokens: psycheTokens + retrievalTokens,
    degraded: psycheStatus === "empty" || ["timeout", "error", "disabled"].includes(retrieval.status),
  };
}

/** Render a manifest as compact, readable text for the explain_context tool. */
export function renderManifest(m: ContextManifest): string {
  const lines = [
    `# glia-context preview (mode=${m.mode}${m.degraded ? ", DEGRADED" : ""})`,
    `~${m.totalTokens} tokens total`,
    "",
    `## Identity (${m.psycheStatus}, ~${m.psycheTokens} tok) — ${m.psycheSource}`,
    m.psycheSections.length ? m.psycheSections.map((s) => `  · ${s}`).join("\n") : "  (no page sections parsed)",
    "",
    `## Retrieval (${m.retrievalStatus}, ~${m.retrievalTokens} tok, ${m.retrievalPages.length} pages)`,
    m.retrievalPages.length
      ? m.retrievalPages.map((p) => `  · ${p.slug}  (${p.score.toFixed(2)})`).join("\n")
      : "  (no pages)",
  ];
  return lines.join("\n");
}

/**
 * The core of the thesis: build the injection that primes the model with WHO
 * YOU ARE (psyche) and, optionally, WHAT'S RELEVANT (gbrain context).
 *
 * Budgeting reflects the blind-judge findings: identity and relevance are
 * COMPLEMENTS, not substitutes. Retrieval is what makes an answer specific and
 * actionable; identity is what makes it insightful. The winning arm carried
 * both. And identity is high-density — a dose-response run found a ~3k-token
 * core (self-page + top essays) reaches ~95% of the full psyche's blind ranking,
 * so it doesn't need the whole file (deepest insight does keep climbing with
 * more, so the cap leaves headroom). So in `both` mode we front-load a CAPPED
 * identity core and hand the larger remainder to retrieval, so the answer stays
 * grounded. (v1's "retrieval dilutes identity" did not survive blind judging —
 * see experiments/psyche-injection/FINDINGS.md.)
 *
 * Never throws. Degrades gracefully AND reports it: a visible `> glia-context
 * status:` block at the top of the returned text names any missing component.
 */
export async function primeContext(
  task: string,
  opts: { mode?: InjectMode; maxTokens?: number } = {},
): Promise<PrimeResult> {
  const mode = opts.mode ?? "both";
  const budget = opts.maxTokens ?? 60_000;

  let psycheText = "";
  let psycheSource = "";
  let psycheStatus: PsycheStatus | "skipped" = "skipped";
  if (mode === "psyche" || mode === "both") {
    const p = await loadPsyche();
    psycheSource = p.source;
    psycheStatus = p.status;
    // Identity is high-density: a concentrated core carries the insight lift.
    // Cap it at 40% of budget in `both` mode so retrieval keeps room to ground.
    const psycheBudget = mode === "psyche" ? budget : Math.floor(budget * 0.4);
    psycheText = p.status === "empty" ? "" : truncateToTokens(p.text, psycheBudget);
  }

  let contextText = "";
  let retrieval: RetrievalResult = { pages: [], status: "skipped", elapsedMs: 0, cached: false, query: task };
  if (mode === "context" || mode === "both") {
    // Dedup: don't spend retrieval budget re-injecting pages the psyche already
    // carries (e.g. a starred essay) — measured ~50% overlap. Only exclude what
    // was ACTUALLY injected (the truncated psycheText), not the full psyche.
    const exclude = mode === "both" && psycheText ? psycheSlugs(psycheText) : undefined;
    retrieval = await retrieveContext(task, { excludeSlugs: exclude });
    const ctx = formatContext(retrieval.pages);
    const ctxBudget = mode === "context" ? budget : budget - estimateTokens(psycheText);
    contextText = ctxBudget > 500 ? truncateToTokens(ctx, ctxBudget) : "";
  }
  // Pages that ACTUALLY made it into the text (may be 0 if the budget dropped
  // the block even though retrieval succeeded) — so status never over-claims.
  const injectedPages = contextText ? retrieval.pages.length : 0;

  const statusLines = buildStatusLines({ mode, psycheStatus, psycheSource, retrieval, injectedPages });
  const degraded = psycheStatus === "empty" || ["timeout", "error", "disabled"].includes(retrieval.status);

  // NB: a visible "how to use this" directive + closing instruction was A/B-tested
  // (GLIA_NO_DIRECTIVE toggle) and came out a dead 50/50 tie with a strong judge —
  // a capable model already serves the specific person from the identity+context,
  // so we DON'T ship the extra tokens. The "call prime_context first / reason from
  // it" guidance lives at the protocol level via the server `instructions` instead.
  const header = [
    "# Priming context for this session",
    "<!-- Injected by glia-context. Below is who I am, then what's relevant to the task.",
    "     Use both to serve me specifically — not generically. -->",
    "",
  ].join("\n");

  const blocks = [header, renderStatusBlock(statusLines, degraded)];
  if (psycheText) blocks.push("## Who I am\n", psycheText, "");
  if (contextText) blocks.push(contextText);
  const text = blocks.join("\n");

  return {
    text,
    mode,
    tokens: estimateTokens(text),
    psycheTokens: estimateTokens(psycheText),
    contextTokens: estimateTokens(contextText),
    contextPages: injectedPages,
    source: psycheSource,
    psycheStatus,
    retrievalStatus: retrieval.status,
    retrievalDetail: retrieval.detail,
    retrievalMs: retrieval.elapsedMs,
    retrievalCached: retrieval.cached,
    degraded,
    statusLines,
  };
}
