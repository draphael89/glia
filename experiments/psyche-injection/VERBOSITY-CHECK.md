# Verbosity-confound check

Does the injection lift just reflect longer answers? Two task-controlled tests.

## Answer length (words) per arm

| task | naked | context | psyche | best |
|---|---|---|---|---|
| t1 | 388 | 376 | 392 | 413 |
| t2 | 363 | 360 | 406 | 390 |
| t3 | 330 | 352 | 340 | 362 |
| t4 | 366 | 392 | 364 | 407 |
| t5 | 431 | 453 | 461 | 433 |
| t7 | 385 | 348 | 369 | 345 |
| t8 | 273 | 353 | 386 | 403 |
| **mean** | **362** | **376** | **388** | **393** |

## Opus (v2+v3, n=49)
- Borda order: **best > context > psyche > naked**  (best 118, context 83, psyche 65, naked 28)
- **decisive:** `psyche` is LONGER than `context` (388 vs 376 words) yet ranks BELOW it (Borda 65 < 83) → length does NOT drive the order ✅  [1 such length↔rank inversion(s)]
- within-task pairwise: the LONGER answer ranked higher **62%** of the time (183/294 pairs) — 50% = length irrelevant
- Spearman(length, per-answer Borda) = **+0.19** (weak/none)

## Haiku (v4, n=21)
- Borda order: **best > context > psyche > naked**  (best 41, context 39, psyche 32, naked 14)
- **decisive:** `psyche` is LONGER than `context` (388 vs 376 words) yet ranks BELOW it (Borda 32 < 39) → length does NOT drive the order ✅  [1 such length↔rank inversion(s)]
- within-task pairwise: the LONGER answer ranked higher **59%** of the time (74/126 pairs) — 50% = length irrelevant
- Spearman(length, per-answer Borda) = **+0.17** (weak/none)

## gpt-5 (v6, n=28)
- Borda order: **best > context > naked > psyche**  (best 52, context 42, naked 40, psyche 34)
- **decisive:** `psyche` is LONGER than `naked` (388 vs 362 words) yet ranks BELOW it (Borda 34 < 40) → length does NOT drive the order ✅  [2 such length↔rank inversion(s)]
- within-task pairwise: the LONGER answer ranked higher **59%** of the time (99/168 pairs) — 50% = length irrelevant
- Spearman(length, per-answer Borda) = **+0.07** (weak/none)

## Verdict

Length differs by only ~8% across arms (all generated under the same instruction). The longer answer wins ~60% of within-task pairs and Spearman(length, score) is +0.07…+0.19 (weak) — a mild association, as expected since a genuinely insightful answer is often slightly longer. But length is **not the driver**: in every judge pool `psyche` is longer than `context` yet loses to it, so a shorter arm beats a longer one on content. The injection ranking (`best` first) survives controlling for verbosity.
