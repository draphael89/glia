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
    const dedup = r.dedupedCount > 0 ? ` (+${r.dedupedCount} already in your identity, deduped)` : "";
    // Retrieval found pages but the token budget left no room for them.
    if (r.pages.length > 0 && a.injectedPages === 0 && (r.status === "ok" || r.status === "empty")) {
      out.push(`retrieval: ${r.pages.length} pages found but dropped — no token budget left after identity`);
    } else if (r.status === "ok") out.push(`retrieval: ${a.injectedPages} pages in ${r.elapsedMs}ms${r.cached ? " (cached)" : ""}${dedup}`);
    // Empty *because* everything relevant is already in the psyche is expected and
    // good on identity-shaped tasks (the v7 finding) — say so, don't imply failure.
    else if (r.status === "empty" && r.dedupedCount > 0) out.push(`retrieval: all ${r.dedupedCount} relevant pages are already in your identity — nothing new to add (expected on identity-shaped tasks)`);
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
  retrievalDeduped: number;   // ranked pages dropped as already-in-identity
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
  // Same assembler as primeContext, so the preview is truthful for ANY budget:
  // same psyche cap, same dedup, same context truncation, same scaffolding.
  const a = await assembleInjection(task, opts);
  const scoreBySlug = new Map(a.retrieval.pages.map((p) => [p.slug, p.score]));
  const pages = a.injectedPageSlugs.map((slug) => ({ slug, score: scoreBySlug.get(slug) ?? 0 }));
  return {
    mode: a.mode,
    psycheStatus: a.psycheStatus,
    psycheSource: a.psycheSource,
    psycheTokens: estimateTokens(a.psycheText),
    psycheSections: a.psycheSections,
    retrievalStatus: a.retrieval.status,
    retrievalPages: pages,                            // only pages that survived truncation
    retrievalTokens: estimateTokens(a.contextText),  // actual injected context tokens
    retrievalDeduped: a.retrieval.dedupedCount,
    totalTokens: estimateTokens(a.text),             // full rendered prime, incl. scaffolding
    degraded: a.degraded,
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
    `## Retrieval (${m.retrievalStatus}, ~${m.retrievalTokens} tok, ${m.retrievalPages.length} pages${m.retrievalDeduped > 0 ? `, ${m.retrievalDeduped} deduped` : ""})`,
    m.retrievalPages.length
      ? m.retrievalPages.map((p) => `  · ${p.slug}  (${p.score.toFixed(2)})`).join("\n")
      : (m.retrievalDeduped > 0
          ? `  (all ${m.retrievalDeduped} relevant pages already in your identity — deduped, nothing new to add)`
          : "  (no pages)"),
  ];
  return lines.join("\n");
}

interface Assembled {
  mode: InjectMode;
  text: string;
  psycheText: string;
  contextText: string;
  psycheStatus: PsycheStatus | "skipped";
  psycheSource: string;
  psycheSections: string[];
  retrieval: RetrievalResult;
  injectedPages: number;
  injectedPageSlugs: string[];
  degraded: boolean;
  statusLines: string[];
}

/** Slugs that survived context truncation — formatContext writes each page as
 *  `### <slug>  _(relevance ...)_`, so the injected subset is what's left. */
function injectedPageSlugsFrom(contextText: string): string[] {
  const out: string[] = [];
  for (const m of contextText.matchAll(/^### (\S+)  _\(relevance/gm)) out.push(m[1]);
  return out;
}

/**
 * The core of the thesis: build the injection that primes the model with WHO
 * YOU ARE (psyche) and, optionally, WHAT'S RELEVANT (gbrain context). This is
 * the SINGLE source of truth shared by primeContext (the real prime) and
 * explainContext (the preview), so the two can never drift.
 *
 * Budgeting reflects the blind-judge findings: identity and relevance are
 * COMPLEMENTS, not substitutes. Retrieval is what makes an answer specific and
 * actionable; identity is what makes it insightful. Identity is high-density —
 * a dose-response run found a ~3k-token core (self-page + top essays) reaches
 * ~95% of the full psyche's blind ranking — so in `both` mode we front-load a
 * CAPPED identity core (40% of budget) and hand the remainder to retrieval, and
 * dedup retrieval against the injected psyche (~50% overlap). Never throws;
 * degrades gracefully AND reports it via a visible `> glia-context status:` block.
 */
async function assembleInjection(
  task: string,
  opts: { mode?: InjectMode; maxTokens?: number },
): Promise<Assembled> {
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

  let contextText = "";
  let retrieval: RetrievalResult = { pages: [], status: "skipped", elapsedMs: 0, cached: false, query: task, dedupedCount: 0 };
  if (mode === "context" || mode === "both") {
    // Dedup against what was ACTUALLY injected (the truncated psycheText).
    const exclude = mode === "both" && psycheText ? psycheSlugs(psycheText) : undefined;
    retrieval = await retrieveContext(task, { excludeSlugs: exclude });
    const ctx = formatContext(retrieval.pages);
    const ctxBudget = mode === "context" ? budget : budget - estimateTokens(psycheText);
    contextText = ctxBudget > 500 ? truncateToTokens(ctx, ctxBudget) : "";
  }

  // Truncation-aware: the pages that actually survived into contextText.
  const injectedPageSlugs = injectedPageSlugsFrom(contextText);
  const injectedPages = injectedPageSlugs.length;

  const statusLines = buildStatusLines({ mode, psycheStatus, psycheSource, retrieval, injectedPages });
  const degraded = psycheStatus === "empty" || ["timeout", "error", "disabled"].includes(retrieval.status);

  // NB: a visible "how to use this" directive was A/B-tested (GLIA_NO_DIRECTIVE)
  // and came out a dead 50/50 tie with a strong judge, so we don't ship the extra
  // tokens; the "prime first" nudge lives in the server `instructions` instead.
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
    mode, text, psycheText, contextText, psycheStatus, psycheSource,
    psycheSections: [...psycheSlugs(psycheText)], retrieval, injectedPages, injectedPageSlugs,
    degraded, statusLines,
  };
}

export async function primeContext(
  task: string,
  opts: { mode?: InjectMode; maxTokens?: number } = {},
): Promise<PrimeResult> {
  const a = await assembleInjection(task, opts);
  return {
    text: a.text,
    mode: a.mode,
    tokens: estimateTokens(a.text),
    psycheTokens: estimateTokens(a.psycheText),
    contextTokens: estimateTokens(a.contextText),
    contextPages: a.injectedPages,
    source: a.psycheSource,
    psycheStatus: a.psycheStatus,
    retrievalStatus: a.retrieval.status,
    retrievalDetail: a.retrieval.detail,
    retrievalMs: a.retrieval.elapsedMs,
    retrievalCached: a.retrieval.cached,
    degraded: a.degraded,
    statusLines: a.statusLines,
  };
}
