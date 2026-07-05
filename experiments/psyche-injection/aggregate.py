#!/usr/bin/env python3
"""Aggregate psyche-injection eval results → REPORT.md.

Reads the workflow's raw output (array of per-task {responses, judgments}),
maps shuffled judge slots back to conditions, and computes Borda scores,
pairwise win rates, and rubric averages — split psyche-sensitive vs control.

Usage: python3 aggregate.py results/raw/results.json
"""
import json
import sys
from pathlib import Path
from collections import defaultdict

CONDITIONS = ["naked", "context", "psyche", "best"]
# MUST match the workflow's PERMS. perm[k] = condition index shown in slot k.
PERMS = [[0, 1, 2, 3], [3, 2, 1, 0], [1, 3, 0, 2],
         [2, 0, 3, 1], [0, 2, 1, 3], [3, 1, 2, 0]]
LETTERS = ["A", "B", "C", "D"]
DIMS = ["specificity", "actionability", "personalFit", "insight"]


def main(path):
    results = json.load(open(path))

    def blank():
        return {c: 0.0 for c in CONDITIONS}

    def analyze(tasks):
        borda = blank()
        n_judgments = 0
        pair_wins = defaultdict(int)   # (winner, loser) -> count
        pair_total = defaultdict(int)
        rubric = {c: {d: [] for d in DIMS} for c in CONDITIONS}
        for t in tasks:
            for j in t.get("judgments", []):
                ranking = j.get("ranking")
                perm = PERMS[j.get("permIdx", 0)]
                if not ranking or len(ranking) != 4:
                    continue
                n_judgments += 1
                # slot letter -> condition
                slot_cond = {LETTERS[k]: CONDITIONS[perm[k]] for k in range(4)}
                # Borda: rank 0 (best) = 3 points ... rank 3 = 0
                ranked_conds = [slot_cond[L] for L in ranking]
                for r, c in enumerate(ranked_conds):
                    borda[c] += (3 - r)
                # pairwise from ranking order
                for a in range(4):
                    for b in range(a + 1, 4):
                        w, lo = ranked_conds[a], ranked_conds[b]
                        pair_wins[(w, lo)] += 1
                        pair_total[(w, lo)] += 1
                        pair_total[(lo, w)] += 1
                # rubric
                scores = j.get("scores") or {}
                for L in LETTERS:
                    c = slot_cond[L]
                    s = scores.get(L) or {}
                    for d in DIMS:
                        if isinstance(s.get(d), (int, float)):
                            rubric[c][d].append(float(s[d]))
        return borda, n_judgments, pair_wins, pair_total, rubric

    sensitive = [t for t in results if t.get("kind") != "control-technical"]
    control = [t for t in results if t.get("kind") == "control-technical"]

    out = []
    out.append("# Psyche Injection — Results\n")
    out.append(f"_{len(results)} tasks · {len(sensitive)} psyche-sensitive + "
               f"{len(control)} technical control · 4 arms · 3 blind judges each_\n")

    def section(title, tasks, note=""):
        if not tasks:
            return
        borda, n, pw, pt, rub = analyze(tasks)
        out.append(f"\n## {title}\n{note}")
        out.append(f"\n**Blind-judge Borda score** (3=best each ranking, "
                   f"{n} judgments):\n")
        ranked = sorted(CONDITIONS, key=lambda c: -borda[c])
        maxb = max(borda.values()) or 1
        for c in ranked:
            bar = "█" * round(20 * borda[c] / maxb)
            out.append(f"- `{c:8}` {borda[c]:5.0f}  {bar}")
        # headline pairwise comparisons
        out.append("\n**Key pairwise win rates:**\n")
        for w, lo in [("context", "naked"), ("psyche", "naked"),
                      ("best", "context"), ("best", "psyche"), ("psyche", "context")]:
            tot = pt[(w, lo)]
            if tot:
                rate = 100 * pw[(w, lo)] / tot
                out.append(f"- **{w}** beats **{lo}**: {rate:.0f}%  ({pw[(w,lo)]}/{tot})")
        # rubric
        out.append("\n**Rubric averages (1-10):**\n")
        out.append("| arm | " + " | ".join(DIMS) + " |")
        out.append("|" + "---|" * (len(DIMS) + 1))
        for c in CONDITIONS:
            vals = []
            for d in DIMS:
                xs = rub[c][d]
                vals.append(f"{sum(xs)/len(xs):.1f}" if xs else "–")
            out.append(f"| {c} | " + " | ".join(vals) + " |")

    section("Psyche-sensitive tasks", sensitive,
            "Tasks where who-you-are plausibly matters (decisions, planning, "
            "writing in-voice, critique of your own thesis, essay framing).")
    section("Technical control", control,
            "_Negative control: the brain holds nothing relevant and psyche "
            "should NOT help. If it wins here, judges are mirroring._")

    # verdict
    if sensitive:
        borda_s, *_ = analyze(sensitive)
        best_arm = max(CONDITIONS, key=lambda c: borda_s[c])
        psyche_lift = borda_s["psyche"] - borda_s["naked"]
        best_lift = borda_s["best"] - borda_s["context"]
        out.append("\n## Verdict\n")
        out.append(f"- Best arm on psyche-sensitive tasks: **{best_arm}**")
        out.append(f"- Psyche vs naked (does identity alone help?): "
                   f"{'+' if psyche_lift>=0 else ''}{psyche_lift:.0f} Borda")
        out.append(f"- Best vs context (does psyche add on top of retrieval?): "
                   f"{'+' if best_lift>=0 else ''}{best_lift:.0f} Borda")

    out.append("\n---\n_Generated by aggregate.py. Threats to validity in "
               "[README](README.md). Small-n pilot; harness scales._")
    report = "\n".join(out) + "\n"
    Path("REPORT.md").write_text(report)
    print(report)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "results/raw/results.json")
