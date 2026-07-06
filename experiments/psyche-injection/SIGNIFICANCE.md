# Significance — how certain is the headline? (task-clustered)

Judgments cluster on 7 tasks, so the honest unit of independence is the *task*, not the individual judgment. Naive binomial-on-judgments would overstate precision; everything below is task-clustered.

## Opus (v2+v3)  (49 judgments over 7 tasks)

### best vs context
- pooled win rate: **71%**  ·  per-task: t1 57%, t2 57%, t3 29%, t4 100%, t5 100%, t7 71%, t8 86%
- sign test across tasks: **6/7** tasks favor `best`  → two-sided p = **0.125** (n=7 is low-powered)
- task-clustered bootstrap 95% CI: **[53%, 88%]** — excludes 50% ✅

### best vs naked
- pooled win rate: **88%**  ·  per-task: t1 29%, t2 100%, t3 100%, t4 100%, t5 100%, t7 86%, t8 100%
- sign test across tasks: **6/7** tasks favor `best`  → two-sided p = **0.125** (n=7 is low-powered)
- task-clustered bootstrap 95% CI: **[67%, 100%]** — excludes 50% ✅

### context vs naked
- pooled win rate: **82%**  ·  per-task: t1 43%, t2 100%, t3 100%, t4 71%, t5 86%, t7 71%, t8 100%
- sign test across tasks: **6/7** tasks favor `context`  → two-sided p = **0.125** (n=7 is low-powered)
- task-clustered bootstrap 95% CI: **[65%, 96%]** — excludes 50% ✅

## gpt-5 (v6, cross-vendor)  (28 judgments over 7 tasks)

### best vs context
- pooled win rate: **64%**  ·  per-task: t1 100%, t2 75%, t3 50%, t4 100%, t5 50%, t7 0%, t8 75%
- sign test across tasks: **4/5** tasks favor `best` (+2 tie)  → two-sided p = **0.375** (n=7 is low-powered)
- task-clustered bootstrap 95% CI: **[39%, 86%]** — **includes 50%** — not resolvable at n=7

### best vs psyche
- pooled win rate: **68%**  ·  per-task: t1 75%, t2 75%, t3 75%, t4 100%, t5 25%, t7 100%, t8 25%
- sign test across tasks: **5/7** tasks favor `best`  → two-sided p = **0.453** (n=7 is low-powered)
- task-clustered bootstrap 95% CI: **[46%, 89%]** — **includes 50%** — not resolvable at n=7

## Reading the two tests

They can disagree (Opus best-vs-context: bootstrap CI excludes 50%, yet the sign test gives p=0.125). The **sign test across tasks is the conservative, trustworthy bound** — its unit is the task (n=7). The bootstrap still credits the many within-task judgments as independent evidence, but those re-rate the *same* four fixed answers, so they mostly capture judge noise, not new signal — its CI is optimistic. When they conflict, believe the sign test.

## v13 — a natural noise-floor experiment (direct evidence for the caveat above)

v13 (retrieval completeness × identity) accidentally supplied the cleanest measurement of
this pilot's noise floor. Its control task **p2** had complete mirror coverage, so its
`context_thin` and `context_full` arms were fed the **same six pages** (identical slugs,
scores, order) — two independently-generated answers from *identical* context. Blind
judges still split them **14 vs 4 of 15 Borda**.

That 10-point swing is a direct read of the per-answer generation+judge variance with the
signal held at zero — and it is **as large as the cross-arm differences** v13 was trying to
measure. It's the empirical version of the point above: the many within-task judgments
mostly re-rate the *same* answers (judge noise); a fresh *generation* of the same input is
a coin-flip on a 4-way rank. So a 5-task run cannot resolve a subtle contrast, and even the
larger v6/v7 pilots should be read as **direction, not decimals**. (This is why v13 is
reported as a null, not a reversal — see `REPORT-v13.md`.)

## Verdict

The **direction** is robust — `best` beats `context` in 6/7 tasks (Opus) and reproduces cross-vendor, and every pooled rate matches the published headline. But **significance is limited by n=7**: the conservative across-task sign test is p≈0.125 even at 6/7 (not <0.05), and the cross-vendor (gpt-5) task-clustered CIs *include* 50%. So: trust the **ordering** (best > context > … , reproduced across three judge vendors and robust to verbosity), treat the **exact percentages and cross-vendor significance as directional**. This is a 7-task pilot; the one fix a re-judge *can't* buy is more tasks. Stated plainly so nobody over-reads the big judgment counts.
