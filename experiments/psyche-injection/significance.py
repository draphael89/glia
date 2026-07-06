#!/usr/bin/env python3
"""How CERTAIN is the headline, honestly? The pooled "best beats context 71%"
treats 49 judgments as independent — but they cluster on just 7 tasks (each task
re-judged many times). Naive binomial CIs would overstate precision. This does
the cluster-correct thing:

  1. Per-task pairwise win rate (best vs context, best vs naked).
  2. Sign test ACROSS tasks (the unit of independence is the task, n=7).
  3. Task-clustered bootstrap: resample the 7 TASKS with replacement (not the
     individual judgments) → 95% CI on the pooled win rate.

If the task-clustered CI is wide or grazes 50%, that's the honest limit of a
7-task pilot — report it, don't hide it behind a big judgment count.
"""
import json, os, random
from collections import defaultdict
from math import comb

random.seed(20260706)   # deterministic; documented seed, not Date/rand-at-import
base = os.path.dirname(os.path.abspath(__file__))
CONDS = ["naked", "context", "psyche", "best"]
PERMS = [[0,1,2,3],[3,2,1,0],[1,3,0,2],[2,0,3,1],[0,2,1,3],[3,1,2,0]]
L = ["A","B","C","D"]

v2 = json.load(open(os.path.join(base, "results/raw/results-v2.json")))
TASKS = [t["taskId"] for t in v2 if not t.get("checkable")]

def rankings(files):
    """taskId -> list of arm-orderings (best..worst) pooled over files."""
    out = defaultdict(list)
    for f in files:
        for t in json.load(open(os.path.join(base, "results/raw", f))):
            if t.get("checkable"): continue
            for j in t.get("blindJudgments", []):
                r = j.get("ranking")
                if not r or len(r) != 4: continue
                sm = {L[k]: CONDS[PERMS[j["permIdx"]][k]] for k in range(4)}
                out[t["taskId"]].append([sm[x] for x in r])
    return out

def above(order, a, b):
    """True if arm a is ranked above arm b in this ordering."""
    return order.index(a) < order.index(b)

def binom_two_sided(k, n, p=0.5):
    """Exact two-sided binomial p-value for k successes in n."""
    if n == 0: return 1.0
    probs = [comb(n, i) * p**i * (1-p)**(n-i) for i in range(n+1)]
    obs = probs[k]
    return min(1.0, sum(pr for pr in probs if pr <= obs + 1e-12))

def analyze(files, label, comparisons):
    R = rankings(files)
    ntask = sum(1 for t in TASKS if R[t])
    out = [f"## {label}  ({sum(len(R[t]) for t in TASKS)} judgments over {ntask} tasks)\n"]
    for a, b in comparisons:
        # per-task win rate of a over b
        per = {}
        for t in TASKS:
            js = R[t]
            if not js: continue
            per[t] = sum(1 for o in js if above(o, a, b)) / len(js)
        tasks = sorted(per)
        # pooled (judgment-weighted) rate
        allj = [(t, o) for t in tasks for o in R[t]]
        pooled = sum(1 for t, o in allj if above(o, a, b)) / len(allj)
        # sign test across tasks: tasks where a wins (>0.5)
        wins = sum(1 for t in tasks if per[t] > 0.5)
        ties = sum(1 for t in tasks if per[t] == 0.5)
        eff = len(tasks) - ties
        p = binom_two_sided(wins, eff) if eff else 1.0
        # task-clustered bootstrap on the pooled rate
        B = 20000; boot = []
        for _ in range(B):
            samp = [random.choice(tasks) for _ in tasks]
            num = den = 0
            for t in samp:
                for o in R[t]:
                    den += 1; num += 1 if above(o, a, b) else 0
            boot.append(num/den)
        boot.sort()
        lo, hi = boot[int(.025*B)], boot[int(.975*B)]
        excl = "excludes 50% ✅" if lo > 0.5 else "**includes 50%** — not resolvable at n=7"
        out.append(f"### {a} vs {b}")
        out.append(f"- pooled win rate: **{pooled*100:.0f}%**  ·  per-task: "
                   + ", ".join(f"{t} {per[t]*100:.0f}%" for t in tasks))
        out.append(f"- sign test across tasks: **{wins}/{eff}** tasks favor `{a}`"
                   + (f" (+{ties} tie)" if ties else "") + f"  → two-sided p = **{p:.3f}**"
                   + (" ✅" if p < 0.05 else " (n=7 is low-powered)"))
        out.append(f"- task-clustered bootstrap 95% CI: **[{lo*100:.0f}%, {hi*100:.0f}%]** — {excl}\n")
    return out

lines = ["# Significance — how certain is the headline? (task-clustered)\n",
         "Judgments cluster on 7 tasks, so the honest unit of independence is the "
         "*task*, not the individual judgment. Naive binomial-on-judgments would "
         "overstate precision; everything below is task-clustered.\n"]
lines += analyze(["results-v2.json", "results-v3.json"], "Opus (v2+v3)",
                 [("best","context"), ("best","naked"), ("context","naked")])
lines += analyze(["results-v6-gpt5.json"], "gpt-5 (v6, cross-vendor)",
                 [("best","context"), ("best","psyche")])
lines.append("## Reading the two tests\n")
lines.append("They can disagree (Opus best-vs-context: bootstrap CI excludes 50%, "
             "yet the sign test gives p=0.125). The **sign test across tasks is the "
             "conservative, trustworthy bound** — its unit is the task (n=7). The "
             "bootstrap still credits the many within-task judgments as independent "
             "evidence, but those re-rate the *same* four fixed answers, so they "
             "mostly capture judge noise, not new signal — its CI is optimistic. "
             "When they conflict, believe the sign test.\n")
lines.append("## Verdict\n")
lines.append("The **direction** is robust — `best` beats `context` in 6/7 tasks "
             "(Opus) and reproduces cross-vendor, and every pooled rate matches the "
             "published headline. But **significance is limited by n=7**: the "
             "conservative across-task sign test is p≈0.125 even at 6/7 (not <0.05), "
             "and the cross-vendor (gpt-5) task-clustered CIs *include* 50%. So: "
             "trust the **ordering** (best > context > … , reproduced across three "
             "judge vendors and robust to verbosity), treat the **exact percentages "
             "and cross-vendor significance as directional**. This is a 7-task "
             "pilot; the one fix a re-judge *can't* buy is more tasks. Stated plainly "
             "so nobody over-reads the big judgment counts.\n")
out = "\n".join(lines)
open(os.path.join(base, "SIGNIFICANCE.md"), "w").write(out)
print(out)
print("wrote SIGNIFICANCE.md")
