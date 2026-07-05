import { readFile, readdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { config } from "./config.js";

/** Strip gbrain frontmatter + fact markers from a page body. */
export function cleanBody(raw: string): string {
  return raw
    .replace(/^---\n[\s\S]*?\n---\n/, "")
    .replace(/<!--- gbrain:facts:begin -->[\s\S]*?<!--- gbrain:facts:end -->/g, "")
    .trim();
}

/** Injection priority: self-page → essays → concepts → rest (mirrors Glia). */
function identityRank(slug: string): number {
  const s = slug.toLowerCase();
  if (s === "people-david" || s.endsWith("/david")) return 0;
  if (s.startsWith("originals/")) return 1;
  if (s.startsWith("concepts/")) return 2;
  if (s.startsWith("people/") || s.startsWith("companies/")) return 3;
  return 4;
}

/**
 * The psyche map — "who you are". Prefers the canonical file Glia exports;
 * falls back to building it live from the gbrain source (self-page + essays)
 * so the server works standalone before Glia has written anything.
 */
export async function loadPsyche(): Promise<{ text: string; source: string }> {
  if (existsSync(config.psycheFile)) {
    const text = await readFile(config.psycheFile, "utf8");
    if (text.trim().length > 200) return { text, source: config.psycheFile };
  }
  return buildPsycheFromSource();
}

/** Fallback: assemble self-page + originals/ essays from the gbrain repo. */
export async function buildPsycheFromSource(): Promise<{ text: string; source: string }> {
  const dir = config.gbrainSourceDir;
  const parts: string[] = ["# Who I am — psyche map", ""];
  const selfCandidates = ["people-david.md", "people/david.md"];
  for (const rel of selfCandidates) {
    const p = join(dir, rel);
    if (existsSync(p)) {
      parts.push("## Self\n", (await readFile(p, "utf8")), "");
      break;
    }
  }
  const originals = join(dir, "originals");
  if (existsSync(originals)) {
    parts.push("## Essays\n");
    const files = (await readdir(originals)).filter((f) => f.endsWith(".md")).sort();
    for (const f of files) {
      parts.push(`### ${f.replace(/\.md$/, "")}`, await readFile(join(originals, f), "utf8"), "\n---");
    }
  }
  return { text: parts.join("\n"), source: `${dir} (self-page + essays)` };
}

export { identityRank };
