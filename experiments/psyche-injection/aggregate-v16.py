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
    out.append(f"\nRound-to-round spread: **{spread:.0f} points** "
               f"(small = the replication genuinely averaged out per-answer noise).")

    out.append("\n## Margins\n" + ", ".join(f"{k}: {v}" for k, v in sorted(margins.items())))

    # Verdict — data-driven
    rate = pct(both, tot)
    out.append("\n## Reading\n")
    if rate >= 60:
        out.append(f"- **Identity beats retrieval-alone at complete retrieval, {rate:.0f}%, with the "
                   f"generation noise averaged out.** This is the resolution v13 couldn't reach: the v12 "
                   f"direction survives BOTH complete retrieval and variance reduction — identity is a genuine "
                   f"complement, not a proxy for pages retrieval was dropping.")
    elif rate >= 53:
        out.append(f"- Identity edges retrieval-alone at complete retrieval ({rate:.0f}%) — a real but modest "
                   f"complement once noise is controlled. Consistent with 'identity helps most when retrieval "
                   f"doesn't already carry it'; at 99% completeness retrieval carries more of it.")
    elif rate >= 47:
        out.append(f"- **A wash ({rate:.0f}%): at complete retrieval, adding identity to retrieval doesn't move "
                   f"the needle** for a verification-blind judge. Complete retrieval already surfaces the identity "
                   f"essays (see the dedup ledger — identity queries dedup hard now), so the separate psyche is "
                   f"largely redundant. The value of identity injection is then concentrated where retrieval is "
                   f"thin or absent — and in what a HUMAN (who can verify the specifics) sees, which LLM judges undercount.")
    else:
        out.append(f"- Retrieval-alone edges the combined arm ({100-rate:.0f}%) at complete retrieval — adding the "
                   f"psyche on top of already-complete retrieval slightly dilutes. Would refine the injection to "
                   f"lean harder on retrieval when it's complete.")
    out.append("- Caveat: still 5 tasks and one generator/judge family; K=3 shrinks the *answer* noise (the v13 "
               "problem) but not task-selection variance. Direction over decimals.")

    report = "\n".join(out) + "\n"
    open(os.path.join(base, "REPORT-v16.md"), "w").write(report)
    print(report)
    print(f"\nwrote {os.path.join(base, 'REPORT-v16.md')}")


if __name__ == "__main__":
    main()
