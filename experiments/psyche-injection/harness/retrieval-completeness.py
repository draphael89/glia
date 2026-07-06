#!/usr/bin/env python3
"""Quantify the retrieval bug that drove the v9->v12 flip.

The glia-context MCP RANKS pages against the whole brain (`gbrain query`) but
historically read page BODIES from a local mirror dir (`~/.gbrain/source-default`)
that is only a SUBSET of the brain. When a top-ranked page was absent from the
mirror it was silently dropped, so the injected `both` arm was fed a thin,
holey context — which is why blind judges preferred retrieval-alone in v9. The
fix: for up to GBRAIN_GET_FALLBACK_MAX top pages that miss the mirror, fall back
to a live `gbrain get <slug>`.

This measures, over a suite of real queries, for the top-K ranked pages per query:
  - mirror HIT  (body already on disk — always readable)
  - mirror MISS (would be STARVED under the old mirror-only path)
  - of the misses, how many the capped `gbrain get` fallback recovers.

Then it reports readable-page counts BEFORE (mirror-only) vs AFTER (mirror + cap)
— the quantitative version of the v12 flip's mechanism.

Aggregates print to stdout; the per-query raw (private slugs) writes to
results/raw/ (gitignored). No brain content is emitted to stdout.
"""
import json, os, subprocess, sys

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOME = os.path.expanduser("~")
GBRAIN = os.environ.get("GBRAIN_CMD", os.path.join(HOME, ".hermes/scripts/gbrain-local.sh"))
MIRROR = os.environ.get("GBRAIN_SOURCE_DIR", os.path.join(HOME, ".gbrain/source-default"))
TOP_K = int(os.environ.get("TOP_K", "8"))            # the injection's top-8 pages
FALLBACK_MAX = int(os.environ.get("GBRAIN_GET_FALLBACK_MAX", "3"))  # the shipped cap

# A diverse suite spanning the kinds of tasks prime_context serves: identity/values,
# work/meetings, product strategy, and technical judgment. (Prompts only — no answers.)
QUERIES = [
    "what matters most in how I make decisions",
    "how do I think about AI alignment and validators",
    "my philosophy on legacy and what I want to leave behind",
    "how should a knowledge graph change real outcomes",
    "what did we decide about the NIL product MVP",
    "how do I approach hiring and evaluating people",
    "the tradeoff between risk and reaching full potential",
    "how I make product prioritization calls",
    "what I believe about personalization and recommendation systems",
    "my views on deterministic gates versus AI judgment",
    "how I think about rootedness and belonging",
    "what makes a good AI reflection of a person",
    "notes from recent meetings about creative pipelines",
    "how I reason about delegation and trust",
    "the relationship between velocity and destination",
]


def query_slugs(q, k):
    """Return the top-k ranked slugs for a query (highest score first)."""
    try:
        out = subprocess.run([GBRAIN, "query", q, "--no-expand"],
                             capture_output=True, text=True, timeout=30).stdout
    except Exception as e:
        print(f"  ! query failed: {e}", file=sys.stderr)
        return []
    slugs = []
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("["):
            continue
        # format: [score] slug -- excerpt
        try:
            rest = line.split("]", 1)[1].strip()
            slug = rest.split(" -- ", 1)[0].strip().split()[0]
        except (IndexError, ValueError):
            continue
        if slug and slug not in slugs:
            slugs.append(slug)
        if len(slugs) >= k:
            break
    return slugs


def mirror_has(slug):
    return os.path.isfile(os.path.join(MIRROR, slug + ".md"))


def get_recovers(slug):
    """True if `gbrain get <slug>` returns a non-trivial body."""
    try:
        out = subprocess.run([GBRAIN, "get", slug],
                             capture_output=True, text=True, timeout=30).stdout
    except Exception:
        return False
    return len(out.strip()) > 40


def main():
    n_mirror = int(subprocess.run(["bash", "-c", f"find {MIRROR} -name '*.md' | wc -l"],
                                  capture_output=True, text=True).stdout.strip() or 0)
    rows = []
    tot_pages = tot_hit = tot_miss = tot_recovered = 0
    before_readable = after_readable = 0

    for q in QUERIES:
        slugs = query_slugs(q, TOP_K)
        if not slugs:
            continue
        hits = [s for s in slugs if mirror_has(s)]
        misses = [s for s in slugs if not mirror_has(s)]
        # cap simulation: the loop walks ranked slugs, spending up to FALLBACK_MAX
        # `gbrain get` calls on the misses it encounters, in rank order.
        recovered, spent = [], 0
        for s in slugs:
            if mirror_has(s):
                continue
            if spent >= FALLBACK_MAX:
                break
            spent += 1
            if get_recovers(s):
                recovered.append(s)
        before = len(hits)                       # mirror-only (v9 path)
        after = len(hits) + len(recovered)       # mirror + capped fallback (shipped)
        rows.append({"query": q, "top": len(slugs), "mirror_hit": len(hits),
                     "mirror_miss": len(misses), "recovered_capped": len(recovered),
                     "before_readable": before, "after_readable": after,
                     "miss_slugs": misses})
        tot_pages += len(slugs); tot_hit += len(hits); tot_miss += len(misses)
        tot_recovered += len(recovered)
        before_readable += before; after_readable += after
        print(f"  {q[:52]:52s}  hit {len(hits)}/{len(slugs)}  miss {len(misses)}"
              f"  +recovered {len(recovered)}  ->  {before}->{after} readable")

    os.makedirs(os.path.join(BASE, "results/raw"), exist_ok=True)
    raw_path = os.path.join(BASE, "results/raw/retrieval-completeness.json")
    json.dump({"mirror_files": n_mirror, "top_k": TOP_K, "fallback_max": FALLBACK_MAX,
               "rows": rows}, open(raw_path, "w"), indent=2)

    pct = lambda a, b: (100.0 * a / b) if b else 0.0
    print("\n" + "=" * 64)
    print("RETRIEVAL COMPLETENESS — mirror-subset starvation & fallback recovery")
    print("=" * 64)
    print(f"mirror files: {n_mirror}   queries: {len(rows)}   top-K per query: {TOP_K}")
    print(f"top-K pages examined:        {tot_pages}")
    print(f"  present in mirror (free):  {tot_hit:3d}  ({pct(tot_hit, tot_pages):.0f}%)")
    print(f"  MISSING from mirror:       {tot_miss:3d}  ({pct(tot_miss, tot_pages):.0f}%)  <- starved under mirror-only")
    print(f"  recovered by capped get:   {tot_recovered:3d}  (cap={FALLBACK_MAX}/query)")
    print("-" * 64)
    print(f"readable top pages BEFORE (mirror-only):  {before_readable:3d}  "
          f"({pct(before_readable, tot_pages):.0f}% of top-K)")
    print(f"readable top pages AFTER  (mirror+get):   {after_readable:3d}  "
          f"({pct(after_readable, tot_pages):.0f}% of top-K)")
    gain = pct(after_readable, tot_pages) - pct(before_readable, tot_pages)
    print(f"completeness gain from the fallback fix:  +{gain:.0f} points")
    print("-" * 64)
    starved = sum(1 for r in rows if r["before_readable"] <= TOP_K // 2)
    print(f"queries starved under mirror-only (<= {TOP_K // 2}/{TOP_K} readable): "
          f"{starved}/{len(rows)}")
    remaining = tot_miss - tot_recovered
    if remaining > 0:
        print(f"NOTE: {remaining} missing pages still dropped past the cap of "
              f"{FALLBACK_MAX}/query — raise GBRAIN_GET_FALLBACK_MAX if these matter.")
    print(f"\nraw -> {raw_path} (gitignored)")


if __name__ == "__main__":
    main()
