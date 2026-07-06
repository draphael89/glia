# Psyche Injection — v7 (expansion run: does it hold on fresh tasks?)

_Original 7 identity tasks (t1-t9) + 7 FRESH pre-registered tasks (t10-t16), generated and blind-judged identically. Attacks the one limit a re-judge can't fix: task count. Opus judge pool throughout._

## Combined identity tasks: 12 tasks, 73 blind judgments

- Borda: best 156, context 134, psyche 91, naked 57  → **best > context > psyche > naked**
- best > context: **59%**
- best > psyche: **75%**
- best > naked: **79%**
- context > naked: **79%**

## Per-task `best` vs `context` (the n-expansion)

| task | kind | judgments | best>context | winner |
|---|---|---|---|---|
| t1 | decision | 7 | 57% | naked |
| t2 | planning | 7 | 57% | best |
| t3 | writing | 7 | 29% | context |
| t4 | critique | 7 | 100% | best |
| t5 | essay | 7 | 100% | psyche |
| t7 | decision | 7 | 71% | best |
| t8 | writing | 7 | 86% | best |
| t10 | decision | 5 | 80% | best |
| t11 | reflection | 5 | 20% | context |
| t12 | technical-decision | 4 | 50% | best |
| t13 | writing | 5 | 20% | naked |
| t14 | planning | 5 | 0% | context |

- **`best` beats `context` in 7/11 tasks** (sign test, two-sided p = **0.549**, n.s.)
- vs the v2/v3-only pilot (6/7, p=0.125): adding fresh tasks made best-vs-context **WEAKER, not stronger** — the pilot was optimistic. The fresh tasks split (best won t10, lost t11/t13/t14), so the marginal identity-over-retrieval effect is smaller and more task-dependent than 7 tasks suggested.

## Pre-registered prediction calibration (v7 tasks)

_Predictions were fixed in tasks-v7.json BEFORE generation._

| task | predicted | best>context | best>naked | matched? |
|---|---|---|---|---|
| t10 | identity-helps | 80% | 80% | yes |
| t11 | identity-helps | 20% | 80% | yes |
| t12 | small-effect | 50% | 100% | yes |
| t13 | identity-helps | 20% | 40% | check |
| t14 | identity-helps | 0% | 20% | check |
| t15 | no-effect | 100% | 0% | check |
| t16 | no-effect | 100% | 100% | check |

## Neutral / control tasks (identity should NOT help)

- **t6** (control-factual): Borda context 20 best 12 psyche 8 naked 2 — spread 2.57/judgment | objective pass: naked 100%, context 100%, psyche 100%, best 100%
- **t9** (control-technical): Borda best 15 psyche 14 context 9 naked 4 — spread 1.57/judgment | objective pass: naked 100%, context 100%, psyche 100%, best 100%
- **t15** (technical-neutral): Borda psyche 14 naked 11 best 5 context 0 — spread 2.80/judgment
- **t16** (control-factual): Borda psyche 15 best 10 naked 5 context 0 — spread 3.00/judgment | objective pass: naked 100%, context 100%, psyche 100%, best 100%

## Verdict — honest, and it tempers the pilot

- **Ordering holds**: `best > context > psyche > naked` on the combined 12-task set (73 judgments); `best` is Borda-first and beats **psyche-alone 75%** and **naked 79%** — injecting identity+retrieval clearly beats identity-alone and beats nothing. Those hold up.
- **But the marginal edge of identity OVER retrieval did NOT replicate.** `best` beats `context` in only **7/11** fresh+old tasks (59% pooled, sign-test p=0.549, n.s.) — down from the 7-task pilot's 71%. The pilot **overstated** best-vs-context; the honest estimate is a coin-flip-plus, not a clear win.
- **Why — the dedup rationale, observed.** On the fresh tasks where `best` lost to `context` (t11, t14), retrieval had already surfaced David's *own essays* (telos, daimon-charter) as the context — so the psyche was redundant and adding it didn't help. Where context was operational, not identity-laden (t10), `best` beat `context` 80%. Identity injection helps over retrieval **exactly when retrieval doesn't already surface the identity** — which is precisely why the production MCP dedups psyche against retrieval.
- **Controls**: on the checkable Bloom-filter task every arm scored 100% objectively — identity adds nothing where the answer is just correct-or-not (blind quality ranks on neutral tasks are noise).

---
_Opus generator + judge; fresh tasks pre-registered; strict per-arm read isolation. aggregate-v7.py; aggregate only._
