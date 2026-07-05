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
 * Psyche is FRONT-LOADED and budgeted first — the pilot eval found identity
 * is the high-density signal and that piling on operational retrieval can
 * dilute it, so if the window is tight the identity survives and context is
 * what gets trimmed.
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
    // psyche gets the lion's share; identity is the finding's high-value signal
    const psycheBudget = mode === "psyche" ? budget : Math.floor(budget * 0.6);
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
