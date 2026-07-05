import { homedir } from "node:os";
import { join } from "node:path";

/** All paths/commands configurable via env so the server is portable. */
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
