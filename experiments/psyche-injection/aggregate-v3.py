#!/usr/bin/env python3
"""Aggregate v2 + v3 together — the confidence run.

The v2 answers are FIXED. v3 re-judges them with more blind judges (5/task) and
more objective scorers (3/control). This script MERGES both runs so every
identity-shaped task has 7 blind judgments and every control has 4 objective
scorers — tightening the ranking intervals without regenerating any answer.

Usage: python3 aggregate-v3.py [results/raw/results-v2.json results/raw/results-v3.json]
"""
import json
import sys
from pathlib import Path
from collections import defaultdict

CONDITIONS = ["naked", "context", "psyche", "best"]
PERMS = [[0, 1, 2, 3], [3, 2, 1, 0], [1, 3, 0, 2],
         [2, 0, 3, 1], [0, 2, 1, 3], [3, 1, 2, 0]]
LETTERS = ["A", "B", "C", "D"]
DIMS = ["specificity", "actionability", "correctness", "insight"]


def slot_map(perm):
    return {LETTERS[k]: CONDITIONS[perm[k]] for k in range(4)}


def load_merged(v2_path, v3_path):
    """Return {taskId: {checkable, blind:[...], obj:[...]}} merged across runs."""
    v2 = {t["taskId"]: t for t in json.load(open(v2_path))}
    v3 = {t["taskId"]: t for t in json.load(open(v3_path))} if Path(v3_path).exists() else {}
    merged = {}
    for tid, t in v2.items():
        blind = list(t.get("blindJudgments") or [])
        obj = []
        if t.get("objective"):
            obj.append(t["objective"])
        if tid in v3:
            blind += list(v3[tid].get("blindJudgments") or [])
            obj += list(v3[tid].get("objectiveScorers") or [])
        merged[tid] = {"checkable": t.get("checkable"), "blind": blind, "obj": obj}
    return merged


def analyze(merged):
    borda = {c: 0.0 for c in CONDITIONS}
    pw, pt = defaultdict(int), defaultdict(int)
    rub = {c: {d: [] for d in DIMS} for c in CONDITIONS}
    per_task_meanrank = {}  # taskId -> {arm: mean Borda points} for consistency
    n = 0
    for tid, t in merged.items():
        if t["checkable"]:
            continue
        tb = {c: [] for c in CONDITIONS}
        for j in t["blind"]:
            r = j.get("ranking")
            if not r or len(r) != 4:
                continue
            n += 1
            sm = slot_map(PERMS[j.get("permIdx", 0)])
            ranked = [sm[L] for L in r]
            for rank, c in enumerate(ranked):
                borda[c] += (3 - rank)
                tb[c].append(3 - rank)
            for a in range(4):
                for b in range(a + 1, 4):
                    pw[(ranked[a], ranked[b])] += 1
                    pt[(ranked[a], ranked[b])] += 1
                    pt[(ranked[b], ranked[a])] += 1
            sc = j.get("scores") or {}
            for L in LETTERS:
                for d in DIMS:
                    v = (sc.get(L) or {}).get(d)
                    if isinstance(v, (int, float)):
                        rub[sm[L]][d].append(float(v))
        per_task_meanrank[tid] = {c: (sum(tb[c]) / len(tb[c]) if tb[c] else 0) for c in CONDITIONS}
    return borda, n, pw, pt, rub, per_task_meanrank


def analyze_obj(merged):
    frac = {c: [] for c in CONDITIONS}
    for tid, t in merged.items():
        if not t["checkable"]:
            continue
        for o in t["obj"]:
            if not o or not o.get("perAnswer"):
                continue
            sm = slot_map(PERMS[o.get("permIdx", 0)])
            npts = o.get("nPoints") or 5
            for L in LETTERS:
                bools = o["perAnswer"].get(L) or []
                if bools:
                    frac[sm[L]].append(sum(1 for x in bools if x) / npts)
    return frac


def main(v2_path, v3_path):
    merged = load_merged(v2_path, v3_path)
    borda, n, pw, pt, rub, ptm = analyze(merged)
    ntasks = sum(1 for t in merged.values() if not t["checkable"])

    out = ["# Psyche Injection — v2+v3 merged (confidence run)\n"]
    out.append(f"_{ntasks} identity-shaped tasks · **{n} blind judgments** "
               f"(v2's 2/task + v3's 5/task = 7/task) · judges blind to the psyche_\n")

    out.append(f"\n## Blind-judge Borda ({n} judgments)\n")
    maxb = max(borda.values()) or 1
    for c in sorted(CONDITIONS, key=lambda x: -borda[x]):
        out.append(f"- `{c:8}` {borda[c]:6.0f}  {'█'*round(24*borda[c]/maxb)}")

    out.append("\n**Pairwise win-rate (blind):**\n")
    for a, b in [("best", "psyche"), ("best", "context"), ("best", "naked"),
                 ("context", "psyche"), ("context", "naked"), ("psyche", "naked")]:
        if pt[(a, b)]:
            out.append(f"- **{a}** > **{b}**: {100*pw[(a,b)]/pt[(a,b)]:.0f}% ({pw[(a,b)]}/{pt[(a,b)]})")

    # per-task consistency: how many tasks does each ordering hold?
    out.append("\n**Consistency across tasks** (mean Borda per task; how often the order holds):\n")
    best_gt_ctx = sum(1 for t in ptm.values() if t["best"] > t["context"])
    best_gt_psy = sum(1 for t in ptm.values() if t["best"] > t["psyche"])
    ctx_gt_psy = sum(1 for t in ptm.values() if t["context"] > t["psyche"])
    out.append(f"- best > context in **{best_gt_ctx}/{ntasks}** tasks")
    out.append(f"- best > psyche in **{best_gt_psy}/{ntasks}** tasks")
    out.append(f"- context > psyche in **{ctx_gt_psy}/{ntasks}** tasks")

    out.append("\n**Blind rubric (1-10):**\n")
    out.append("| arm | " + " | ".join(DIMS) + " | n |")
    out.append("|" + "---|" * (len(DIMS) + 2))
    for c in CONDITIONS:
        vals = [f"{sum(rub[c][d])/len(rub[c][d]):.1f}" if rub[c][d] else "–" for d in DIMS]
        cnt = len(rub[c][DIMS[0]])
        out.append(f"| {c} | " + " | ".join(vals) + f" | {cnt} |")

    frac = analyze_obj(merged)
    nctrl = sum(1 for t in merged.values() if t["checkable"])
    out.append(f"\n## Objective correctness — {nctrl} neutral controls, 4 scorers each\n")
    out.append("| arm | rubric-point pass rate |")
    out.append("|---|---|")
    for c in CONDITIONS:
        xs = frac[c]
        out.append(f"| {c} | {100*sum(xs)/len(xs):.0f}% ({len(xs)} gradings) |" if xs else f"| {c} | – |")

    out.append("\n## Verdict\n")
    lead = max(CONDITIONS, key=lambda c: borda[c])
    out.append(f"- **{lead}** leads the blind Borda over {n} judgments — "
               f"{'the combined arm, as v2 found. More judges did not overturn it.' if lead=='best' else 'CHANGED from v2 — investigate.'}")
    out.append(f"- best > context holds in {best_gt_ctx}/{ntasks} tasks and "
               f"{100*pw[('best','context')]/pt[('best','context')]:.0f}% pairwise → "
               f"{'robust: adding identity to retrieval helps.' if best_gt_ctx > ntasks/2 else 'fragile — near coin-flip.'}")
    pm = sum(frac['psyche'])/len(frac['psyche']) if frac['psyche'] else 0
    nm = sum(frac['naked'])/len(frac['naked']) if frac['naked'] else 0
    out.append(f"- Neutral controls: psyche {100*pm:.0f}% vs naked {100*nm:.0f}% "
               f"({'≈ equal — identity lift is task-specific, not a global effort bump.' if abs(pm-nm)<0.12 else 'diverge — re-examine.'})")

    out.append("\n---\n_Generated by aggregate-v3.py. Merges v2+v3; answers fixed, judges added._")
    Path("REPORT-v3.md").write_text("\n".join(out) + "\n")
    print("\n".join(out))


if __name__ == "__main__":
    a = sys.argv[1] if len(sys.argv) > 1 else "results/raw/results-v2.json"
    b = sys.argv[2] if len(sys.argv) > 2 else "results/raw/results-v3.json"
    main(a, b)
