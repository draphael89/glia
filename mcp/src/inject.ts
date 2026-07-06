import { config, estimateTokens, truncateToTokens } from "./config.js";
import { loadPsyche } from "./psyche.js";
import { retrieveContext, formatContext, type RetrievedPage } from "./gbrain.js";

export type InjectMode = "psyche" | "context" | "both";

export interface PrimeResult {
  text: string;
  mode: InjectMode;
  tokens: number;
  psycheTokens: number;
  contextTokens: number;
  contextPages: number;
  source: string;
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
 */
export async function primeContext(
  task: string,
  opts: { mode?: InjectMode; maxTokens?: number } = {},
): Promise<PrimeResult> {
  const mode = opts.mode ?? "both";
  const budget = opts.maxTokens ?? 60_000;

  let psycheText = "";
  let psycheSource = "";
  if (mode === "psyche" || mode === "both") {
    const p = await loadPsyche();
    psycheSource = p.source;
    // Identity is high-density: a concentrated core carries the insight lift.
    // Cap it at 40% of budget in `both` mode so retrieval keeps room to ground.
    const psycheBudget = mode === "psyche" ? budget : Math.floor(budget * 0.4);
    psycheText = truncateToTokens(p.text, psycheBudget);
  }

  let contextText = "";
  let pages: RetrievedPage[] = [];
  if (mode === "context" || mode === "both") {
    pages = await retrieveContext(task);
    const ctx = formatContext(pages);
    const ctxBudget = mode === "context" ? budget : budget - estimateTokens(psycheText);
    contextText = ctxBudget > 500 ? truncateToTokens(ctx, ctxBudget) : "";
  }

  const header = [
    "# Priming context for this session",
    "<!-- Injected by glia-context. Below is who I am, then what's relevant to the task.",
    "     Use both to serve me specifically — not generically. -->",
    "",
  ].join("\n");

  const blocks = [header];
  if (psycheText) blocks.push("## Who I am\n", psycheText, "");
  if (contextText) blocks.push(contextText);
  const text = blocks.join("\n");

  return {
    text,
    mode,
    tokens: estimateTokens(text),
    psycheTokens: estimateTokens(psycheText),
    contextTokens: estimateTokens(contextText),
    contextPages: pages.length,
    source: psycheSource,
  };
}
