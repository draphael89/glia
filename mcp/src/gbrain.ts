import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { readFile } from "node:fs/promises";
import { existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { config } from "./config.js";
import { cleanBody } from "./psyche.js";

const pexec = promisify(execFile);

export interface RetrievedPage {
  slug: string;
  score: number;
  body: string;
}

/**
 * Relevant context for a query, from gbrain. Runs `gbrain query`, parses the
 * ranked slugs, and reads each page's full body from the source mirror.
 * Degrades gracefully: if gbrain isn't reachable, returns [].
 */
export async function retrieveContext(
  query: string,
  opts: { topK?: number; maxCharsPerPage?: number } = {},
): Promise<RetrievedPage[]> {
  const topK = opts.topK ?? 6;
  const maxChars = opts.maxCharsPerPage ?? 6000;
  let stdout = "";
  try {
    const r = await pexec(config.gbrainCmd, ["query", query, "--no-expand"], {
      timeout: 60_000,
      maxBuffer: 8 * 1024 * 1024,
    });
    stdout = r.stdout;
  } catch (e: any) {
    // gbrain unavailable — retrieval is best-effort, psyche still works.
    stdout = e?.stdout ?? "";
  }

  const ranked: { slug: string; score: number }[] = [];
  for (const line of stdout.split("\n")) {
    const m = line.match(/^\s*\[([\d.]+)\]\s+(\S+)\s+--/);
    if (m) ranked.push({ score: parseFloat(m[1]), slug: m[2] });
  }

  const pages: RetrievedPage[] = [];
  for (const { slug, score } of ranked.slice(0, topK)) {
    const file = join(config.gbrainSourceDir, `${slug}.md`);
    if (existsSync(file) && statSync(file).size < 40_000) {
      const body = cleanBody(await readFile(file, "utf8")).slice(0, maxChars);
      if (body.length > 0) pages.push({ slug, score, body });
    }
  }
  return pages;
}

export function formatContext(pages: RetrievedPage[]): string {
  if (pages.length === 0) return "";
  const parts = ["## Relevant context", ""];
  for (const p of pages) parts.push(`### ${p.slug}  _(relevance ${p.score.toFixed(2)})_\n\n${p.body}\n\n---`);
  return parts.join("\n");
}
