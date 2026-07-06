#!/usr/bin/env python3
"""Aggregate v17 — does v16's task-shape finding REPLICATE on fresh tasks?

v16 found (on 5 tasks) that identity beats retrieval-alone on generative/synthesis-from-self
tasks and loses on the diagnostic one. v17 pre-registers the split: 4 GENERATIVE + 4
DIAGNOSTIC fresh tasks, variance-reduced (K=3 gens/arm) blind pairwise both-vs-context at
complete retrieval. If generative both-win >> diagnostic both-win, the finding replicates.

Reads results/raw/results-v17.json. Writes REPORT-v17.md. Aggregate only.
Result shape: [{taskId, type, prompt, rounds: [{round, votes: [{bothWon, margin}]}]}]
"""
import json, os, sys
from collections import defaultdict

base = os.path.dirname(os.path.abspath(__file__))


def main():
    fname = sys.argv[1] if len(sys.argv) > 1 else "results/raw/results-v17.json"
    path = fname if os.path.isabs(fname) else os.path.join(base, fname)
    if not os.path.exists(path):
        print(f"{fname} not present yet — run the workflow, save its result there."); return
    data = json.load(open(path))

    by_type = defaultdict(lambda: [0, 0])   # type -> [both_wins, total]
    per_task = {}
    per_round = defaultdict(lambda: [0, 0])
    tot = both = 0
    for t in data:
        ty = t.get("type", "?"); tb = tt = 0
        for rnd in t.get("rounds", []):
            for v in rnd.get("votes", []):
                tot += 1; tt += 1; w = 1 if v.get("bothWon") else 0
                both += w; tb += w
                by_type[ty][0] += w; by_type[ty][1] += 1
                pr = per_round[rnd["round"]]; pr[0] += w; pr[1] += 1
        per_task[t["taskId"]] = (ty, tb, tt)

    pct = lambda a, b: (100.0 * a / b) if b else float("nan")
    out = ["# Psyche Injection — v17 (does the task-shape finding replicate?)\n"]
    out.append(f"Blind pairwise votes: **{tot}** (8 fresh tasks × K=3 gens × 3 judges). "
               f"Each = retrieval-alone vs retrieval+identity, at 99%-complete retrieval.\n")

    out.append("## The pre-registered test — by task TYPE\n| type | both beats context | |\n|---|---|---|")
    g = by_type.get("generative", [0, 0]); d = by_type.get("diagnostic", [0, 0])
    out.append(f"| **generative** (synthesis-from-self) | **{pct(*g):.0f}%** | {g[0]}/{g[1]} |")
    out.append(f"| **diagnostic** (fact-lookup) | **{pct(*d):.0f}%** | {d[0]}/{d[1]} |")
    gap = pct(*g) - pct(*d)
    out.append(f"\n**Generative − diagnostic gap: {gap:+.0f} points.**\n")

    out.append("## Per-task\n| task | type | both-wins | rate |\n|---|---|---|---|")
    for tid in sorted(per_task):
        ty, w, n = per_task[tid]
        out.append(f"| {tid} | {ty} | {w}/{n} | {pct(w, n):.0f}% |")

    out.append("\n## Per generation-round (noise check)\n| round | rate |\n|---|---|")
    for r in sorted(per_round):
        w, n = per_round[r]
        out.append(f"| {r} | {pct(w, n):.0f}% |")
    rates = [pct(w, n) for w, n in per_round.values() if n]
    spread = (max(rates) - min(rates)) if rates else 0

    out.append(f"\n## Reading\n")
    if gap >= 25:
        out.append(f"- **The task-shape finding REPLICATES.** On fresh, pre-registered tasks, identity beats "
                   f"retrieval-alone {pct(*g):.0f}% on generative/synthesis-from-self tasks but only {pct(*d):.0f}% "
                   f"on diagnostic/fact-lookup tasks — a {gap:+.0f}-point gap. This is the project's sharpest, most "
                   f"durable claim: **identity injection is a complement whose value is conditional on task shape** — "
                   f"real when the answer is synthesized from who you are, redundant when it's just the relevant facts. "
                   f"It validates the two-tool design (prime_context for synthesis, recall for lookups).")
    elif gap >= 10:
        out.append(f"- The task-shape pattern **partially replicates** ({gap:+.0f}-pt gap: generative {pct(*g):.0f}% vs "
                   f"diagnostic {pct(*d):.0f}%) — directionally consistent with v16 but softer. Identity helps more on "
                   f"generative tasks, but the line is fuzzier than v16's 5-task split suggested.")
    elif gap <= -10:
        out.append(f"- **Does NOT replicate — reversed** (diagnostic {pct(*d):.0f}% > generative {pct(*g):.0f}%). v16's "
                   f"split was likely task-specific noise, not a task-shape law. Walk back the heterogeneity claim.")
    else:
        out.append(f"- **Does not clearly replicate** (gap {gap:+.0f} pts). Both types land near {pct(both, tot):.0f}% "
                   f"pooled — the generative/diagnostic distinction from v16 doesn't hold up on fresh tasks at this n. "
                   f"Treat v16's per-task pattern as suggestive, not established.")
    out.append(f"- Overall: both beats context {pct(both, tot):.0f}% pooled. Round-to-round spread {spread:.0f} pts "
               f"({'noise well-controlled' if spread <= 20 else 'noise still substantial even at K=3'}). "
               f"Caveats: 8 tasks, one generator/judge family, one person's brain. Direction + the type-gap, not decimals.")

    report = "\n".join(out) + "\n"
    open(os.path.join(base, "REPORT-v17.md"), "w").write(report)
    print(report)
    print(f"\nwrote {os.path.join(base, 'REPORT-v17.md')}")


if __name__ == "__main__":
    main()
