#!/usr/bin/env python3
"""Compare the shipped `both` config (v9: 24k psyche core) against the rebalanced
one (v10: ~4k core + fuller retrieval) on the SAME production tasks. The v9 finding
was that shipped-both LOST to retrieval-alone; v10 tests whether shrinking the core
(which also un-dedups retrieval) recovers the combined arm. Same tasks, same
context/psyche/naked arms — only the `both` (best) injection differs.

Reads results/raw/results-v9.json + results-v10.json. Prints a side-by-side.
"""
import json, os
from collections import defaultdict

CONDS = ["naked", "context", "psyche", "best"]
PERMS = [[0,1,2,3],[3,2,1,0],[1,3,0,2],[2,0,3,1],[0,2,1,3],[3,1,2,0]]
L = ["A","B","C","D"]
base = os.path.dirname(os.path.abspath(__file__))


def analyze(path):
    if not os.path.exists(path):
        return None
    borda = {c: 0 for c in CONDS}; pw = defaultdict(int); pt = defaultdict(int); n = 0
    for t in json.load(open(path)):
        for j in t.get("blindJudgments", []):
            r = j.get("ranking")
            if not r or len(r) != 4 or len(set(r)) != 4:
                continue
            sm = {L[k]: CONDS[PERMS[j["permIdx"]][k]] for k in range(4)}
            ranked = [sm[x] for x in r]
            if set(ranked) != set(CONDS):
                continue
            n += 1
            for i, c in enumerate(ranked):
                borda[c] += 3 - i
            for a in range(4):
                for b in range(a + 1, 4):
                    pw[(ranked[a], ranked[b])] += 1
                    pt[(ranked[a], ranked[b])] += 1; pt[(ranked[b], ranked[a])] += 1
    return borda, pw, pt, n


def line(label, res):
    if not res:
        return f"| {label} | (not run yet) | | | |"
    borda, pw, pt, n = res
    order = sorted(CONDS, key=lambda c: -borda[c])
    bc = f"{100*pw[('best','context')]/pt[('best','context')]:.0f}%" if pt[('best','context')] else "-"
    bn = f"{100*pw[('best','naked')]/pt[('best','naked')]:.0f}%" if pt[('best','naked')] else "-"
    return f"| {label} | {' > '.join(order)} | {bc} | {bn} | {n} |"


def main():
    v9 = analyze(os.path.join(base, "results/raw/results-v9.json"))
    v10 = analyze(os.path.join(base, "results/raw/results-v10.json"))
    out = ["# both-mode config comparison — does a focused core recover the combined arm?\n",
           "| config | Borda order | best>context | best>naked | judgments |",
           "|---|---|---|---|---|",
           line("v9  (24k core, shipped)", v9),
           line("v10 (~4k core, rebalanced)", v10), ""]
    if v9 and v10:
        b9, _, _, _ = v9; b10, _, _, _ = v10
        o9 = sorted(CONDS, key=lambda c: -b9[c]); o10 = sorted(CONDS, key=lambda c: -b10[c])
        recovered = o10[0] == "best" or (o10.index("best") < o10.index("context"))
        out.append("## Verdict\n")
        if recovered:
            out.append("- **The rebalanced core RECOVERS the combined arm.** Shrinking the identity core "
                       "to ~4k (which also un-dedups retrieval, so `best` keeps the relevant pages as "
                       "focused ranked context) moves `best` back ahead of `context` — the shipped 24k "
                       "config was over-dosing the psyche and starving retrieval. Ship the smaller core.")
        else:
            out.append("- **Rebalancing did NOT flip the order** — `best` still doesn't lead `context` "
                       f"(v9 {' > '.join(o9)} → v10 {' > '.join(o10)}). The shipped both-mode's shortfall "
                       "isn't just the core size; identity's marginal value over natural-query retrieval "
                       "is genuinely thin in production. Keep the honest v9 finding.")
    out.append("\n_Same 5 production tasks; only the both injection differs. compare-configs.py; aggregate only._")
    open(os.path.join(base, "REPORT-config-compare.md"), "w").write("\n".join(out) + "\n")
    print("\n".join(out))


if __name__ == "__main__":
    main()
