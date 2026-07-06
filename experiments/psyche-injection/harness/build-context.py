#!/usr/bin/env python3
"""Build a task's `context` material the SAME way the original v2 files were made,
so expansion tasks stay methodologically identical: gbrain hybrid-query for the
task topic -> keep the top substantive pages (drop operational dumps) -> read each
full body with `gbrain get` -> concatenate as `## <slug>` sections.

Usage:  build-context.py <taskId> "<retrieval query>" [topK]
Writes: materials/<taskId>-context.md   (gitignored — private brain data)

The `context` and `best` arms read this file; keeping the builder in-repo makes
the grounding reproducible and auditable (only the OUTPUT is private, not the
method).
"""
import os, sys, subprocess, re

GBRAIN = os.path.expanduser("~/.hermes/scripts/gbrain-local.sh")
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAT = os.path.join(BASE, "materials")

# Operational/provenance dumps that pollute grounding — same spirit as the
# retrieval hygiene excludes in gbrain-local.sh. Keep substantive knowledge pages
# (plans/originals/people/concepts/notes/briefs/atoms/reports/orchestration/…).
NOISE = re.compile(r"^(sources/|.*/snapshots/|.*/\.raw/|attachments/|test/)", re.I)
# Skip giant index/dump pages (open-loops, orphan-index are 140KB+ firehoses that
# aren't focused grounding). Mirrors the MCP's gbrainMaxPageBytes philosophy and
# keeps context files in the same 12-36KB band as the original v2 materials.
MAX_PAGE_CHARS = 30_000

def run(args, timeout=90):
    return subprocess.run(["perl", "-e", "alarm shift; exec @ARGV", str(timeout), GBRAIN, *args],
                          capture_output=True, text=True).stdout

def query_slugs(q, topk):
    out = run(["query", q, "--no-expand"])
    slugs = []
    for line in out.splitlines():
        m = re.match(r"\[([\d.]+)\]\s+(\S+)", line)
        if not m:
            continue
        score, slug = float(m.group(1)), m.group(2)
        if NOISE.match(slug):
            continue
        slugs.append((slug, score))
        if len(slugs) >= topk:
            break
    return slugs

def main():
    if len(sys.argv) < 3:
        sys.exit("usage: build-context.py <taskId> \"<query>\" [topK]")
    tid, q = sys.argv[1], sys.argv[2]
    topk = int(sys.argv[3]) if len(sys.argv) > 3 else 7
    slugs = query_slugs(q, topk)
    if not slugs:
        sys.exit(f"no substantive slugs for '{q}' — refine the query")
    parts = [f"# Relevant context for {tid}\n"]
    kept = []
    for slug, score in slugs:
        body = run(["get", slug]).strip()
        if not body or len(body) < 40:
            continue
        if len(body) > MAX_PAGE_CHARS:   # skip firehose index/dump pages
            print(f"   (skip {slug}: {len(body)} chars > cap)")
            continue
        parts.append(f"## {slug}\n{body}\n")
        kept.append((slug, score, len(body)))
    dest = os.path.join(MAT, f"{tid}-context.md")
    open(dest, "w").write("\n".join(parts))
    total = sum(k[2] for k in kept)
    print(f"{tid}: {len(kept)} pages, {total} chars -> {dest}")
    for slug, score, n in kept:
        print(f"   [{score:.3f}] {slug}  ({n} chars)")

if __name__ == "__main__":
    main()
