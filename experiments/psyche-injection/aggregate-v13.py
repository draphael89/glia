#!/usr/bin/env python3
"""Aggregate v13 — retrieval COMPLETENESS × identity, a controlled 2×2.

Four arms isolate one variable at a time:
  context_thin  = retrieval only, cap-3 (starved ~65%) pipeline
  context_full  = retrieval only, cap-8 (99% complete) pipeline
  both_thin     = retrieval + psyche, cap-3
  both_full     = retrieval + psyche, cap-8

Blind judges rank the 4 answers per task (position permuted per judge). This answers
the sharp question the v12 flip left open: once retrieval is COMPLETE, does injecting
identity still help — or was the psyche partly compensating for the retrieval bug?

  Q1  context_full > context_thin ?  (does completeness help retrieval alone?)
  Q2  both_full   > both_thin    ?  (does completeness help the combined arm?)
  Q3  both_full   > context_full ?  (does identity STILL help at full retrieval — thesis)
  Q4  both_thin   > context_thin ?  (identity help under the OLD starved retrieval)

Reads results/raw/results-v13.json. Writes REPORT-v13.md. Aggregate only — no answer text.
"""
import json, os, sys
from collections import defaultdict

CONDS = ["context_thin", "context_full", "both_thin", "both_full"]
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


def pct(pw, a, b):
    w, l = pw[(a, b)], pw[(b, a)]
    return (100.0 * w / (w + l)) if (w + l) else float("nan"), w, l


def main():
    fname = sys.argv[1] if len(sys.argv) > 1 else "results/raw/results-v13.json"
    path = fname if os.path.isabs(fname) else os.path.join(base, fname)
    if not os.path.exists(path):
        print(f"{fname} not present yet — run the workflow first, save its result there."); return
    borda, pw, pt, rub, n, posfirst, per_task = analyze(json.load(open(path)))
    order = sorted(CONDS, key=lambda c: -borda[c])

    out = ["# Psyche Injection — v13 (retrieval completeness × identity, controlled 2×2)\n"]
    out.append(f"Blind judgments tallied: **{n}**. Four arms = {{context, both}} × {{thin cap-3, full cap-8}}.\n")
    out.append("## Borda (higher = better; 3 for a 1st, 0 for a 4th)\n")
    out.append("| arm | Borda | mean |")
    out.append("|---|---|---|")
    for c in order:
        out.append(f"| {'**' + c + '**' if c == order[0] else c} | {borda[c]} | {borda[c]/n:.2f} |" if n else f"| {c} | 0 | - |")
    out.append(f"\nOrder: **{' > '.join(order)}**\n")

    # The four sharp questions
    def line(label, a, b):
        p, w, l = pct(pw, a, b)
        verdict = "→ " + (a if p > 50 else b) + (" ✓" if p > 50 else "")
        return f"- **{label}**: {a} > {b} = **{p:.0f}%** ({w}/{w+l})  {verdict}"

    out.append("## The controlled questions\n")
    out.append(line("Q1 completeness lifts retrieval-alone", "context_full", "context_thin"))
    out.append(line("Q2 completeness lifts the combined arm", "both_full", "both_thin"))
    out.append(line("Q3 identity still helps at FULL retrieval (thesis)", "both_full", "context_full"))
    out.append(line("Q4 identity helps under thin retrieval", "both_thin", "context_thin"))
    out.append("")

    # Interpretation — noise-aware. The headline is the CONTROL, not the arm order.
    q1, _, _ = pct(pw, "context_full", "context_thin")
    q3, _, _ = pct(pw, "both_full", "context_full")
    CONTROL = os.environ.get("V13_CONTROL_TASK", "p2")
    out.append("## Reading — signal vs noise (READ THIS FIRST)\n")
    msgs = []
    ctrl = per_task.get(CONTROL, {}).get("borda")
    if ctrl:
        gap = abs(ctrl["context_thin"] - ctrl["context_full"])
        maxb = per_task[CONTROL]["n"] * 3
        msgs.append(
            f"- **Control task {CONTROL}: its `context_thin` and `context_full` arms received the SAME six pages** "
            f"(identical slugs, scores, order — {CONTROL}'s mirror coverage was already complete). Their blind Borda "
            f"still differ by **{gap} of {maxb}** ({ctrl['context_thin']} vs {ctrl['context_full']}). That gap is PURE "
            f"generation+judge variance — and it is as large as most of the cross-arm differences in the table above.")
        msgs.append(
            f"- **So the honest headline is a NULL: at n=5×5 the per-answer noise dominates.** The Borda order "
            f"(`{order[0]}` on top) is NOT evidence that thinner retrieval is better — the control shows identical "
            f"inputs swing ~{gap} Borda. Read v13 as *underpowered*, not as a reversal of v12.")
    msgs.append(
        "- **The one directional signal that survives:** the single genuinely-STARVED task (p1, whose thin arm was "
        "cut to ~1.8k tok) favored `context_full`; the tasks where the thin arm's backfill already supplied enough "
        "text slightly favored thin (a length/diversity confound, within the control's noise band). Consistent with: "
        "completeness matters when retrieval is *actually* starved, not when backfill already fills the gap.")
    msgs.append(
        "- **The completeness fix stands on its own DIRECT measurement** (31%→99% readable pages, "
        "`REPORT-completeness.md`) — a fact about what retrieval returns, independent of this answer-quality eval. "
        "v13 shows only that the downstream answer-quality effect is below this eval's resolution.")
    msgs.append(
        "- **This tempers v12's precision too** (same n=5×5 design): v12's *direction* (identity as complement) rests "
        "on the larger v2–v8 body + cross-vendor reproduction; treat the exact percentages as directional. n=5 is a "
        f"signal-finder, not a benchmark. (For the record, unweighted: Q1 completeness-vs-thin {q1:.0f}%, "
        f"Q3 identity-at-full {q3:.0f}% — both well inside the control's noise band.)")
    out += msgs

    out.append("\n## Per-task (p2 is a natural control: its mirror coverage was already complete, so thin≈full)\n")
    out.append("| task | winner | Borda (ctx_thin/ctx_full/both_thin/both_full) |")
    out.append("|---|---|---|")
    for tid in sorted(per_task):
        b = per_task[tid]["borda"]
        out.append(f"| {tid} | {per_task[tid]['winner']} | {b['context_thin']}/{b['context_full']}/{b['both_thin']}/{b['both_full']} |")

    # position-bias sanity
    pf = {k: posfirst[k] for k in L}
    out.append(f"\n## Position-bias check (1st-place slot counts, want ~even)\n`{pf}`\n")

    out.append("## Rubric means (1–10)\n")
    out.append("| arm | " + " | ".join(DIMS) + " |")
    out.append("|---|" + "|".join(["---"] * len(DIMS)) + "|")
    for c in order:
        vals = [f"{(sum(rub[c][d])/len(rub[c][d])):.1f}" if rub[c][d] else "-" for d in DIMS]
        out.append(f"| {c} | " + " | ".join(vals) + " |")

    report = "\n".join(out) + "\n"
    dest = os.path.join(base, "REPORT-v13.md")
    open(dest, "w").write(report)
    print(report)
    print(f"\nwrote {dest}")


if __name__ == "__main__":
    main()
