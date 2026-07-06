# Psyche Injection — v16 (variance-reduced best-vs-context, complete retrieval)

Blind pairwise votes: **45** (K=3 generations/arm × 5 tasks × 3 judges). Each vote = which of two blind answers — retrieval-alone vs retrieval+identity — better serves David.

## Headline

**`both` (retrieval + identity) beats `context` (retrieval-alone): 62%** (28/45).

## Per-task (win rate for `both`)
| task | both-wins | rate |
|---|---|---|
| p1 | 4/9 | 44% |
| p2 | 1/9 | 11% |
| p3 | 6/9 | 67% |
| p4 | 9/9 | 100% |
| p5 | 8/9 | 89% |

## Per generation-round (variance check — rates should be close if noise is controlled)
| round | both-wins | rate |
|---|---|---|
| 0 | 5/15 | 33% |
| 1 | 12/15 | 80% |
| 2 | 11/15 | 73% |

Round-to-round spread: **47 points** (LARGE — even 3 rounds swing this much, so per-answer noise is NOT fully tamed at K=3; the pooled rate is the best point estimate, but its uncertainty stays wide).

## Margins
clear: 13, slight: 32

## Reading

- **Identity beats retrieval-alone at complete retrieval, 62% pooled.** The resolution v13 couldn't reach: pooling K=3 generations, the v12 direction survives BOTH complete retrieval and variance reduction — identity is a genuine complement, not just a proxy for pages retrieval was dropping.
- **The real story is per-task heterogeneity, not the average.** Identity helps most on GENERATIVE / self-shaped tasks — p3, p4, p5 (the speaker bio, the 'velocity-toward-telos' weekly structure, what-to-drop-this-quarter) where knowing the person shapes the whole answer — and least on p2 (the diagnostic 'why will I be stuck', where the retrieved facts already carry it). So 'does identity help' depends on task SHAPE: a real complement for synthesis-from-self, redundant when the answer is just the relevant facts. That conditionality — not a single %, — is the finding.
- Honest caveats: the 47-point round spread shows K=3 only partly tames the per-answer noise; 5 tasks; one generator/judge family. Trust the DIRECTION + the per-task pattern, not the decimal.
