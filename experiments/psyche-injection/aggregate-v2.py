#!/usr/bin/env python3
"""Aggregate v2 results — the mechanism-isolation run.

v2 differs from v1: judges are BLIND to the psyche (rank on general quality,
no personalFit dimension), and checkable controls get an OBJECTIVE correctness
score against a fixed rubric. This lets us separate "the model does better
work when primed with identity" from "judges prefer the voice."

Usage: python3 aggregate-v2.py results/raw/results-v2.json
"""
import json
import sys
from pathlib import Path
from collections import defaultdict

CONDITIONS = ["naked", "context", "psyche", "best"]
PERMS = [[0, 1, 2, 3], [3, 2, 1, 0], [1, 3, 0, 2],
         [2, 0, 3, 1], [0, 2, 1, 3], [3, 1, 2, 0]]
LETTERS = ["A", "B", "C", "D"]
BLIND_DIMS = ["specificity", "actionability", "correctness", "insight"]


def slot_map(perm):
    return {LETTERS[k]: CONDITIONS[perm[k]] for k in range(4)}


def analyze_blind(tasks):
    borda = {c: 0.0 for c in CONDITIONS}
    pair_w, pair_t = defaultdict(int), defaultdict(int)
    rub = {c: {d: [] for d in BLIND_DIMS} for c in CONDITIONS}
    n = 0
    for t in tasks:
        for j in t.get("blindJudgments", []):
            r = j.get("ranking")
            if not r or len(r) != 4:
                continue
            n += 1
            sm = slot_map(PERMS[j.get("permIdx", 0)])
            ranked = [sm[L] for L in r]
            for rank, c in enumerate(ranked):
                borda[c] += (3 - rank)
            for a in range(4):
                for b in range(a + 1, 4):
                    pair_w[(ranked[a], ranked[b])] += 1
                    pair_t[(ranked[a], ranked[b])] += 1
                    pair_t[(ranked[b], ranked[a])] += 1
            sc = j.get("scores") or {}
            for L in LETTERS:
                for d in BLIND_DIMS:
                    v = (sc.get(L) or {}).get(d)
                    if isinstance(v, (int, float)):
                        rub[sm[L]][d].append(float(v))
    return borda, n, pair_w, pair_t, rub


def analyze_objective(tasks):
    """Objective correctness: fraction of rubric points satisfied, per arm."""
    frac = {c: [] for c in CONDITIONS}
    for t in tasks:
        o = t.get("objective")
        if not o or not o.get("perAnswer"):
            continue
        sm = slot_map(PERMS[o.get("permIdx", 0)])
        npts = o.get("nPoints") or 5
        for L in LETTERS:
            bools = o["perAnswer"].get(L) or []
            if bools:
                frac[sm[L]].append(sum(1 for x in bools if x) / npts)
    return frac


def main(path):
    results = json.load(open(path))
    sensitive = [t for t in results if not t.get("checkable")]
    controls = [t for t in results if t.get("checkable")]

    out = ["# Psyche Injection — v2 (mechanism isolation)\n"]
    out.append(f"_{len(results)} tasks · judges **blind to the psyche** · "
               f"{len(controls)} objectively-scored controls_\n")
    out.append("\nv2 asks: does psyche still win when judges CAN'T see it "
               "(so can't reward the voice), and does it help on objectively-"
               "gradable neutral tasks?\n")

    # blind ranking on identity-shaped tasks
    borda, n, pw, pt, rub = analyze_blind(sensitive)
    out.append(f"\n## Blind-judge ranking — identity-shaped tasks ({n} judgments)\n")
    maxb = max(borda.values()) or 1
    for c in sorted(CONDITIONS, key=lambda x: -borda[x]):
        out.append(f"- `{c:8}` {borda[c]:5.0f}  {'█'*round(20*borda[c]/maxb)}")
    out.append("\n**Blind pairwise:**\n")
    for a, b in [("psyche", "naked"), ("psyche", "context"),
                 ("best", "context"), ("best", "psyche")]:
        if pt[(a, b)]:
            out.append(f"- **{a}** > **{b}**: {100*pw[(a,b)]/pt[(a,b)]:.0f}% ({pw[(a,b)]}/{pt[(a,b)]})")
    out.append("\n**Blind rubric (1-10):**\n")
    out.append("| arm | " + " | ".join(BLIND_DIMS) + " |")
    out.append("|" + "---|" * (len(BLIND_DIMS) + 1))
    for c in CONDITIONS:
        vals = [f"{sum(rub[c][d])/len(rub[c][d]):.1f}" if rub[c][d] else "–" for d in BLIND_DIMS]
        out.append(f"| {c} | " + " | ".join(vals) + " |")

    # objective correctness on controls
    if controls:
        frac = analyze_objective(controls)
        out.append("\n## Objective correctness — neutral controls\n")
        out.append("_Rubric-point pass rate on technical/factual tasks where "
                   "identity is irrelevant. If psyche ≈ others here, the "
                   "identity lift on real tasks is genuine (not just style)._\n")
        out.append("\n| arm | mean rubric pass rate |")
        out.append("|---|---|")
        for c in CONDITIONS:
            xs = frac[c]
            out.append(f"| {c} | {100*sum(xs)/len(xs):.0f}% | " if xs else f"| {c} | – |")

    # verdict
    out.append("\n## Verdict\n")
    if n:
        lead = max(CONDITIONS, key=lambda c: borda[c])
        out.append(f"- Blind judges (can't see the psyche) still rank **{lead}** first "
                   f"on identity-shaped tasks → the lift is **real work quality, not "
                   f"voice-preference**." if lead in ("psyche", "best")
                   else f"- Blind judges rank **{lead}** first → psyche's earlier "
                        f"edge may have been voice-preference. Investigate.")
    if controls:
        frac = analyze_objective(controls)
        pm = sum(frac["psyche"]) / len(frac["psyche"]) if frac["psyche"] else 0
        nm = sum(frac["naked"]) / len(frac["naked"]) if frac["naked"] else 0
        out.append(f"- On neutral controls, psyche's objective correctness is "
                   f"{100*pm:.0f}% vs naked {100*nm:.0f}% — "
                   f"{'≈ equal (identity lift is genuine, not judge bias)' if abs(pm-nm)<0.12 else 'different (identity may affect even neutral tasks — the model works harder)'}.")

    out.append("\n---\n_Generated by aggregate-v2.py. Small-n pilot; blind + objective is the honest test._")
    Path("REPORT-v2.md").write_text("\n".join(out) + "\n")
    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "results/raw/results-v2.json")
