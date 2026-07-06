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

/** Read a 0..1 fraction env var, falling back on a bad/out-of-range value. */
function fracEnv(name: string, def: number): number {
  const raw = process.env[name];
  if (raw == null || raw.trim() === "") return def;
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 0 || n > 1) {
    console.error(`glia-context: ${name}="${raw}" is not a 0..1 fraction — using default ${def}`);
    return def;
  }
  return n;
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
  /** Skip a retrieved page whose source file exceeds this (only the first
   *  ~6000 chars are injected anyway; this just avoids reading pathological
   *  multi-hundred-KB raw dumps). Was an over-aggressive 40KB that dropped
   *  high-value ranked pages. */
  gbrainMaxPageBytes: intEnv("GBRAIN_MAX_PAGE_BYTES", 500_000),
  /** Backfill stops once a candidate's score drops below this FRACTION of the
   *  top candidate's score — so the topK budget isn't spent injecting weakly
   *  ranked pages as noise just to hit the count. 0 disables the floor. */
  gbrainRelScoreFloor: fracEnv("GBRAIN_REL_SCORE_FLOOR", 0.5),
  /** The identity self-page slug (rank-0 in the psyche). Env-overridable so the
   *  OSS multi-user build isn't hardcoded to one person. */
  selfSlug: (process.env.GLIA_SELF_SLUG || "people-david").trim().toLowerCase(),
  /** Ceiling on a single identity-source read (psyche file, self-page, each
   *  essay). Bounds memory if a psyche file is huge/binary — far above any real
   *  psyche (~100-250KB) but blocks a pathological multi-MB read per prime. */
  psycheMaxBytes: intEnv("GLIA_PSYCHE_MAX_BYTES", 2_000_000),
  /** Absolute cap on the injected identity core in `both` mode (on top of the 40%
   *  budget share). Tunable, but the default 24k is VALIDATED: v10 tested shrinking
   *  it to 4k (the "focus the core + un-dedup retrieval" hypothesis from v9) and it
   *  made the combined arm WORSE, not better (best-vs-context fell 52%→24%) — more
   *  psyche helps, consistent with v5's dose-response. Don't lower it expecting a win. */
  psycheCoreMaxTokens: intEnv("GLIA_PSYCHE_CORE_MAX_TOKENS", 24_000),
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
