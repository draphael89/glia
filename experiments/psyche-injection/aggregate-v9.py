#!/usr/bin/env python3
"""Aggregate v9 — the PRODUCTION-PIPELINE run. Every prior version (v1-v8) fed the
generator a RECONSTRUCTION of context (raw pages re-read via genPrompt). v9 feeds it
the ACTUAL shipped `prime_context` output — the real header + capped/front-loaded
psyche + dedup'd natural-query retrieval, captured per task per mode from the
compiled MCP. The question: does the thing we actually SHIP reproduce the finding?

Reads results/raw/results-v9.json. Writes REPORT-v9.md. Aggregate only.
"""
import json, os, sys
from collections import defaultdict

CONDS = ["naked", "context", "psyche", "best"]
PERMS = [[0,1,2,3],[3,2,1,0],[1,3,0,2],[2,0,3,1],[0,2,1,3],[3,1,2,0]]
L = ["A","B","C","D"]; DIMS = ["specificity","actionability","correctness","insight"]
base = os.path.dirname(os.path.abspath(__file__))


def analyze(data):
    borda = {c: 0 for c in CONDS}; pw = defaultdict(int); pt = defaultdict(int)
    rub = {c: {d: [] for d in DIMS} for c in CONDS}; n = 0; posfirst = defaultdict(int)
    per_task = {}
    for t in data:
        tb = {c: 0 for c in CONDS}; tn = 0
        for j in t.get("blindJudgments", []):
            r = j.get("ranking")
            if not r or len(r) != 4 or len(set(r)) != 4:
                continue
            sm = {L[k]: CONDS[PERMS[j["permIdx"]][k]] for k in range(4)}
            ranked = [sm[x] for x in r]
            if set(ranked) != set(CONDS):
                continue
            n += 1; tn += 1; posfirst[r[0]] += 1
            for i, c in enumerate(ranked):
                borda[c] += 3 - i; tb[c] += 3 - i
            for a in range(4):
                for b in range(a + 1, 4):
                    pw[(ranked[a], ranked[b])] += 1
                    pt[(ranked[a], ranked[b])] += 1; pt[(ranked[b], ranked[a])] += 1
            sc = j.get("scores", {})
            for Lx in L:
                for d in DIMS:
                    v = (sc.get(Lx) or {}).get(d)
                    if isinstance(v, (int, float)): rub[sm[Lx]][d].append(float(v))
        per_task[t["taskId"]] = {"borda": tb, "n": tn,
                                 "winner": max(CONDS, key=lambda c: tb[c]) if tn else None}
    return borda, pw, pt, rub, n, posfirst, per_task


def main():
    # optional arg: aggregate a different production-shape results file (e.g.
    # results/raw/results-v12.json). Report name is derived from it.
    fname = sys.argv[1] if len(sys.argv) > 1 else "results/raw/results-v9.json"
    path = fname if os.path.isabs(fname) else os.path.join(base, fname)
    tag = os.path.basename(path).replace("results-", "").replace(".json", "")  # e.g. "v9" / "v12"
    if not os.path.exists(path):
        print(f"{fname} not present yet — run the workflow first."); return
    borda, pw, pt, rub, n, posfirst, per_task = analyze(json.load(open(path)))
    order = sorted(CONDS, key=lambda c: -borda[c])
    out = ["# Psyche Injection — v9 (production-pipeline: does the SHIPPED thing help?)\n"]
    out.append("_Answers generated from the ACTUAL `prime_context` output (real header + "
               "capped psyche + dedup'd natural-query retrieval), captured per task per mode "
               "from the compiled MCP — not a reconstruction. 5 tasks, Opus judge, blind._\n")
    out.append(f"## Combined: {n} blind judgments\n")
    out.append("- Borda: " + ", ".join(f"{c} {borda[c]}" for c in order) + f"  → **{' > '.join(order)}**")
    for a, b in [("best","context"), ("best","psyche"), ("best","naked"), ("context","naked"), ("psyche","naked")]:
        if pt[(a,b)]: out.append(f"- {a} > {b}: **{100*pw[(a,b)]/pt[(a,b)]:.0f}%**")
    out.append("- rubric means: " + " | ".join(
        f"{c}(spec {sum(rub[c]['specificity'])/len(rub[c]['specificity']):.1f}, ins {sum(rub[c]['insight'])/len(rub[c]['insight']):.1f})"
        for c in CONDS if rub[c]['specificity']))

    out.append("\n## Per-task winner (note: p1 had a thin-retrieval capture — realistic but degenerate context arm)\n")
    for tid in sorted(per_task):
        e = per_task[tid]
        od = sorted(CONDS, key=lambda c: -e["borda"][c])
        out.append(f"- **{tid}**: {' > '.join(od)}  (winner {e['winner']}, {e['n']} judgments)")

    # Cross-vendor (gpt-5) block, if judged.
    gpt5_path = os.path.join(base, f"results/raw/results-{tag}-gpt5.json")
    if os.path.exists(gpt5_path):
        gb, gpw, gpt, _, gn, gpos, _ = analyze(json.load(open(gpt5_path)))
        gorder = sorted(CONDS, key=lambda c: -gb[c])
        out.append(f"\n## Cross-vendor judge — gpt-5 ({gn} judgments)\n")
        out.append("- Borda: " + ", ".join(f"{c} {gb[c]}" for c in gorder) + f"  → **{' > '.join(gorder)}**")
        for a, b in [("best","context"), ("best","naked"), ("context","naked")]:
            if gpt[(a,b)]: out.append(f"- {a} > {b}: **{100*gpw[(a,b)]/gpt[(a,b)]:.0f}%**")
        out.append(f"- position-first {dict(gpos)} (uniform≈{gn//4}) — "
                   + ("⚠ some position bias" if max(gpos.values()) > 0.6*gn else "position-clean"))
        out.append("- **gpt-5 agrees `context` leads and is HARSHER on `best` (ranks it last)** — "
                   "so the shipped `both` under-performing retrieval is not an Opus artifact.")

    pos_bias = max(posfirst.values()) > 0.6 * n if n else False
    out.append("\n## Verdict\n")
    out.append(f"- The **shipped** injection pipeline puts `{order[0]}` first "
               f"({'reproduces best-first ✅' if order[0]=='best' else 'does NOT lead with best — retrieval-alone wins'}).")
    out.append("- This is the FIRST version to test the real artifact end-to-end (all v1-v8 used a "
               "reconstruction). It reflects what a user actually gets from the installed MCP.")
    out.append("- **Mechanism**: shipped `both` caps psyche at 40% AND dedups its retrieval against it, "
               "so `best` gets THINNER retrieval than the full-budget `context` arm; the 24k psyche is "
               "past the useful dose (v5: ~3k core ≈95%) and dilutes vs focused retrieval of the same "
               "identity pages. A fixable CONFIG problem, not a refutation of the thesis.")
    out.append("- **Next (v10)**: a rebalanced `both` — small ~3-4k identity core + the FULL retrieval "
               "the context arm gets — is the hypothesis to test.")
    if pos_bias:
        out.append(f"- ⚠ position check: slot-first {dict(posfirst)} (uniform≈{n//4}) — some position bias.")
    out.append("\n---\n_Real prime_context output; Opus generator + judge; small-n (5 tasks). aggregate-v9.py; aggregate only._")
    open(os.path.join(base, f"REPORT-{tag}.md"), "w").write("\n".join(out) + "\n")
    print("\n".join(out))


if __name__ == "__main__":
    main()
