import { homedir } from "node:os";
import { join } from "node:path";

/** Read a positive-integer env var, logging (to stderr) + falling back on a bad
 *  value so a typo can't silently disable a timeout. */
function intEnv(name: string, def: number): number {
  const raw = process.env[name];
  if (raw == null || raw.trim() === "") return def;
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) {
    console.error(`glia-context: ${name}="${raw}" is not a positive number — using default ${def}`);
    return def;
  }
  return Math.floor(n);
}

/** All paths/commands/tunables configurable via env so the server is portable. */
export const config = {
  /** Canonical psyche map Glia writes (File > Export Context → identity). */
  psycheFile: process.env.GLIA_PSYCHE ?? join(homedir(), ".glia", "psyche.md"),
  /** gbrain markdown source dir — fallback psyche build + page reads. */
  gbrainSourceDir:
    process.env.GBRAIN_SOURCE_DIR ?? join(homedir(), ".gbrain", "source-default"),
  /** Command to run gbrain retrieval. On this machine, the local wrapper. */
  gbrainCmd:
    process.env.GBRAIN_CMD ??
    join(homedir(), ".hermes", "scripts", "gbrain-local.sh"),
  /** Rough tokens-per-char for budgeting (≈4 chars/token). */
  charsPerToken: 4,
  /** Hard cap on a single gbrain retrieval so a hung brain can't stall a session. */
  gbrainTimeoutMs: intEnv("GBRAIN_TIMEOUT_MS", 8_000),
  /** Positive-result cache TTL (a repeated query within this window is free). */
  gbrainCacheTtlMs: intEnv("GBRAIN_CACHE_TTL_MS", 60_000),
  /** Failure cache TTL — short, so a broken gbrain isn't hammered yet recovers fast. */
  gbrainNegativeCacheTtlMs: intEnv("GBRAIN_NEG_CACHE_TTL_MS", 5_000),
  /** execFile stdout ceiling for a retrieval. */
  gbrainMaxBuffer: 8 * 1024 * 1024,
  /** GLIA_STRICT_STARTUP=1 → exit on any failed config check, not just fatal. */
  strictStartup: process.env.GLIA_STRICT_STARTUP === "1",
};

export function estimateTokens(text: string): number {
  return Math.ceil(text.length / config.charsPerToken);
}

export function truncateToTokens(text: string, maxTokens: number): string {
  const maxChars = maxTokens * config.charsPerToken;
  if (text.length <= maxChars) return text;
  // cut on a paragraph boundary when possible
  const cut = text.lastIndexOf("\n\n", maxChars);
  return text.slice(0, cut > maxChars * 0.6 ? cut : maxChars) + "\n\n…[truncated to fit budget]";
}
