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

/** Where the identity came from: the canonical Glia export, a live build from
 *  the gbrain source, or nothing at all (identity unavailable). */
export type PsycheStatus = "file" | "built" | "empty";
export interface PsycheResult { text: string; source: string; status: PsycheStatus; }

/**
 * The psyche map — "who you are". Prefers the canonical file Glia exports;
 * falls back to building it live from the gbrain source (self-page + essays)
 * so the server works standalone before Glia has written anything.
 */
export async function loadPsyche(): Promise<PsycheResult> {
  try {
    if (existsSync(config.psycheFile)) {
      const text = await readFile(config.psycheFile, "utf8");
      if (text.trim().length > 200) return { text, source: config.psycheFile, status: "file" };
    }
  } catch {
    // unreadable canonical file — fall through to building from source
  }
  return buildPsycheFromSource();
}

/** Fallback: assemble self-page + originals/ essays from the gbrain repo. */
export async function buildPsycheFromSource(): Promise<PsycheResult> {
  const dir = config.gbrainSourceDir;
  const parts: string[] = ["# Who I am — psyche map", ""];
  let found = 0;
  try {
    const selfCandidates = ["people-david.md", "people/david.md"];
    for (const rel of selfCandidates) {
      const p = join(dir, rel);
      if (existsSync(p)) {
        // Emit the same `*<type> · <slug>*` marker Glia's ContextBundle uses, so
        // psycheSlugs can dedup retrieval against the built psyche too (not just
        // the canonical file).
        const slug = rel.replace(/\.md$/, "");
        parts.push(`## Self\n*person · ${slug}*\n`, await readFile(p, "utf8"), "");
        found++;
        break;
      }
    }
    const originals = join(dir, "originals");
    if (existsSync(originals)) {
      const files = (await readdir(originals)).filter((f) => f.endsWith(".md")).sort();
      if (files.length > 0) parts.push("## Essays\n");
      for (const f of files) {
        const slug = `originals/${f.replace(/\.md$/, "")}`;
        parts.push(`### ${slug}\n*original · ${slug}*\n`, await readFile(join(originals, f), "utf8"), "\n---");
        found++;
      }
    }
  } catch {
    // unreadable source dir — degrade to empty rather than throw
  }
  if (found === 0) return { text: "", source: `${dir} (empty)`, status: "empty" };
  return { text: parts.join("\n"), source: `${dir} (self-page + essays)`, status: "built" };
}

/** Page slugs present in an injected psyche block — each page is written as
 *  `*<type> · <slug>*`. Anchored on the leading `*<type>` so it won't false-match
 *  ordinary prose like `foo · bar *baz*`. Lowercased for case-insensitive match. */
export function psycheSlugs(text: string): Set<string> {
  const out = new Set<string>();
  for (const m of text.matchAll(/\*[^*·\n]+·\s+([^\s*]+)\*/g)) out.add(m[1].toLowerCase());
  return out;
}

export { identityRank };
