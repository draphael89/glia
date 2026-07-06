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

    # Interpretation — data-driven
    q1, _, _ = pct(pw, "context_full", "context_thin")
    q3, _, _ = pct(pw, "both_full", "context_full")
    q4, _, _ = pct(pw, "both_thin", "context_thin")
    out.append("## Reading\n")
    msgs = []
    if q1 > 50:
        msgs.append(f"- Completeness **helps retrieval alone** ({q1:.0f}%) — the fix improves the product even before identity.")
    else:
        msgs.append(f"- Completeness did not clearly lift retrieval-alone here ({q1:.0f}%) — content changed more than quantity (full retrieval is higher-relevance, sometimes shorter).")
    if q3 > 50:
        msgs.append(f"- **Identity STILL helps at full retrieval** ({q3:.0f}%): the psyche is a genuine complement, not a proxy for missing pages. This is the strongest form of the thesis — it survives even when retrieval is complete.")
    else:
        msgs.append(f"- At full retrieval, identity's edge narrows to {q3:.0f}% — complete retrieval surfaces the identity essays itself, so a separate psyche is partly redundant (consistent with prime_context's dedup).")
    if q4 > 50 and q3 > 50:
        d = q4 - q3
        rel = "larger" if d > 0 else "smaller"
        msgs.append(f"- Identity's margin is {rel} under thin retrieval ({q4:.0f}%) than full ({q3:.0f}%) — some of the psyche's v12 value was compensating for starved retrieval, but a real complement remains at completeness.")
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
