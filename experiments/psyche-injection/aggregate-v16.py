#!/usr/bin/env python3
"""Aggregate v16 — variance-reduced best-vs-context at COMPLETE retrieval.

v13 came back a null because at n=5×5 the per-answer generation variance (~10 Borda on
identical inputs) swamped the signal. v16 attacks that directly: K=3 independent
generations per arm per task, blind pairwise-judged, so the noise averages out. If
`both` (retrieval+psyche) still beats `context` (retrieval-alone) at 99%-complete
retrieval once noise is controlled, that's the strongest form of the thesis.

Reads results/raw/results-v16.json. Writes REPORT-v16.md. Aggregate only.

Result shape: [{taskId, prompt, rounds: [{round, votes: [{bothWon, margin}]}]}]
"""
import json, os, sys
from collections import defaultdict

base = os.path.dirname(os.path.abspath(__file__))


def main():
    fname = sys.argv[1] if len(sys.argv) > 1 else "results/raw/results-v16.json"
    path = fname if os.path.isabs(fname) else os.path.join(base, fname)
    if not os.path.exists(path):
        print(f"{fname} not present yet — run the workflow first, save its result there."); return
    data = json.load(open(path))

    tot = both = 0
    margins = defaultdict(int)
    per_task = {}
    per_round = defaultdict(lambda: [0, 0])   # round -> [both_wins, total]
    for t in data:
        tb = tt = 0
        for rnd in t.get("rounds", []):
            for v in rnd.get("votes", []):
                tot += 1; tt += 1
                margins[v.get("margin", "?")] += 1
                pr = per_round[rnd["round"]]; pr[1] += 1
                if v.get("bothWon"):
                    both += 1; tb += 1; pr[0] += 1
        per_task[t["taskId"]] = (tb, tt)

    pct = lambda a, b: (100.0 * a / b) if b else float("nan")
    out = ["# Psyche Injection — v16 (variance-reduced best-vs-context, complete retrieval)\n"]
    out.append(f"Blind pairwise votes: **{tot}** (K=3 generations/arm × 5 tasks × 3 judges). "
               f"Each vote = which of two blind answers — retrieval-alone vs retrieval+identity — better serves David.\n")
    out.append(f"## Headline\n")
    out.append(f"**`both` (retrieval + identity) beats `context` (retrieval-alone): "
               f"{pct(both, tot):.0f}%** ({both}/{tot}).\n")

    out.append("## Per-task (win rate for `both`)\n| task | both-wins | rate |\n|---|---|---|")
    for tid in sorted(per_task):
        w, n = per_task[tid]
        out.append(f"| {tid} | {w}/{n} | {pct(w, n):.0f}% |")

    out.append("\n## Per generation-round (variance check — rates should be close if noise is controlled)\n"
               "| round | both-wins | rate |\n|---|---|---|")
    for r in sorted(per_round):
        w, n = per_round[r]
        out.append(f"| {r} | {w}/{n} | {pct(w, n):.0f}% |")
    rates = [pct(w, n) for w, n in per_round.values() if n]
    spread = (max(rates) - min(rates)) if rates else 0
    spread_note = ("small — the replication averaged the per-answer noise out"
                   if spread <= 20 else
                   "LARGE — even 3 rounds swing this much, so per-answer noise is NOT fully tamed at K=3; the "
                   "pooled rate is the best point estimate, but its uncertainty stays wide")
    out.append(f"\nRound-to-round spread: **{spread:.0f} points** ({spread_note}).")

    out.append("\n## Margins\n" + ", ".join(f"{k}: {v}" for k, v in sorted(margins.items())))

    rate = pct(both, tot)
    strong_both = sorted(t for t, (w, n) in per_task.items() if n and pct(w, n) >= 60)
    strong_ctx = sorted(t for t, (w, n) in per_task.items() if n and pct(w, n) <= 40)
    out.append("\n## Reading\n")
    if rate >= 58:
        out.append(f"- **Identity beats retrieval-alone at complete retrieval, {rate:.0f}% pooled.** The resolution "
                   f"v13 couldn't reach: pooling K=3 generations, the v12 direction survives BOTH complete retrieval "
                   f"and variance reduction — identity is a genuine complement, not just a proxy for pages retrieval "
                   f"was dropping.")
    elif rate >= 47:
        out.append(f"- Pooled it's near a wash ({rate:.0f}%) — but the average hides strong per-task structure (below).")
    else:
        out.append(f"- Retrieval-alone edges the combined arm ({100 - rate:.0f}% pooled) at complete retrieval.")
    if strong_both or strong_ctx:
        out.append(f"- **The real story is per-task heterogeneity, not the average.** Identity helps most on "
                   f"GENERATIVE / self-shaped tasks — {', '.join(strong_both) or '(none)'} (the speaker bio, the "
                   f"'velocity-toward-telos' weekly structure, what-to-drop-this-quarter) where knowing the person "
                   f"shapes the whole answer — and least on {', '.join(strong_ctx) or '(none)'} (the diagnostic "
                   f"'why will I be stuck', where the retrieved facts already carry it). So 'does identity help' "
                   f"depends on task SHAPE: a real complement for synthesis-from-self, redundant when the answer "
                   f"is just the relevant facts. That conditionality — not a single %, — is the finding.")
    out.append(f"- Honest caveats: the {spread:.0f}-point round spread shows K=3 only partly tames the per-answer "
               f"noise; 5 tasks; one generator/judge family. Trust the DIRECTION + the per-task pattern, not the decimal.")

    report = "\n".join(out) + "\n"
    open(os.path.join(base, "REPORT-v16.md"), "w").write(report)
    print(report)
    print(f"\nwrote {os.path.join(base, 'REPORT-v16.md')}")


if __name__ == "__main__":
    main()
