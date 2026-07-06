# Psyche Injection — v13 (retrieval completeness × identity, controlled 2×2)

Blind judgments tallied: **25**. Four arms = {context, both} × {thin cap-3, full cap-8}.

## Borda (higher = better; 3 for a 1st, 0 for a 4th)

| arm | Borda | mean |
|---|---|---|
| **context_thin** | 54 | 2.16 |
| both_thin | 49 | 1.96 |
| context_full | 29 | 1.16 |
| both_full | 18 | 0.72 |

Order: **context_thin > both_thin > context_full > both_full**

## The controlled questions

- **Q1 completeness lifts retrieval-alone**: context_full > context_thin = **28%** (7/25)  → context_thin
- **Q2 completeness lifts the combined arm**: both_full > both_thin = **20%** (5/25)  → both_thin
- **Q3 identity still helps at FULL retrieval (thesis)**: both_full > context_full = **40%** (10/25)  → context_full
- **Q4 identity helps under thin retrieval**: both_thin > context_thin = **44%** (11/25)  → context_thin

## Reading — signal vs noise (READ THIS FIRST)

- **Control task p2: its `context_thin` and `context_full` arms received the SAME six pages** (identical slugs, scores, order — p2's mirror coverage was already complete). Their blind Borda still differ by **10 of 15** (14 vs 4). That gap is PURE generation+judge variance — and it is as large as most of the cross-arm differences in the table above.
- **So the honest headline is a NULL: at n=5×5 the per-answer noise dominates.** The Borda order (`context_thin` on top) is NOT evidence that thinner retrieval is better — the control shows identical inputs swing ~10 Borda. Read v13 as *underpowered*, not as a reversal of v12.
- **The one directional signal that survives:** the single genuinely-STARVED task (p1, whose thin arm was cut to ~1.8k tok) favored `context_full`; the tasks where the thin arm's backfill already supplied enough text slightly favored thin (a length/diversity confound, within the control's noise band). Consistent with: completeness matters when retrieval is *actually* starved, not when backfill already fills the gap.
- **The completeness fix stands on its own DIRECT measurement** (31%→99% readable pages, `REPORT-completeness.md`) — a fact about what retrieval returns, independent of this answer-quality eval. v13 shows only that the downstream answer-quality effect is below this eval's resolution.
- **This tempers v12's precision too** (same n=5×5 design): v12's *direction* (identity as complement) rests on the larger v2–v8 body + cross-vendor reproduction; treat the exact percentages as directional. n=5 is a signal-finder, not a benchmark. (For the record, unweighted: Q1 completeness-vs-thin 28%, Q3 identity-at-full 40% — both well inside the control's noise band.)

## Per-task (p2 is a natural control: its mirror coverage was already complete, so thin≈full)

| task | winner | Borda (ctx_thin/ctx_full/both_thin/both_full) |
|---|---|---|
| p1 | context_full | 9/12/4/5 |
| p2 | context_thin | 14/4/11/1 |
| p3 | both_thin | 10/4/14/2 |
| p4 | context_thin | 11/2/9/8 |
| p5 | both_thin | 10/7/11/2 |

## Position-bias check (1st-place slot counts, want ~even)
`{'A': 2, 'B': 6, 'C': 10, 'D': 7}`

## Rubric means (1–10)

| arm | specificity | actionability | correctness | insight |
|---|---|---|---|---|
| context_thin | 8.7 | 8.6 | 8.6 | 8.2 |
| both_thin | 8.2 | 7.6 | 8.6 | 8.9 |
| context_full | 8.2 | 8.1 | 8.0 | 7.4 |
| both_full | 7.7 | 7.0 | 7.5 | 8.2 |
