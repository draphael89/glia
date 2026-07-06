# Psyche Injection — v9 (production-pipeline: does the SHIPPED thing help?)

_Answers generated from the ACTUAL `prime_context` output (real header + capped psyche + dedup'd natural-query retrieval), captured per task per mode from the compiled MCP — not a reconstruction. 5 tasks, Opus judge, blind._

## Combined: 25 blind judgments

- Borda: context 44, best 41, psyche 35, naked 30  → **context > best > psyche > naked**
- best > context: **52%**
- best > psyche: **52%**
- best > naked: **60%**
- context > naked: **72%**
- psyche > naked: **48%**
- rubric means: naked(spec 8.1, ins 7.7) | context(spec 8.3, ins 8.1) | psyche(spec 7.9, ins 8.6) | best(spec 8.2, ins 8.5)

## Per-task winner (note: p1 had a thin-retrieval capture — realistic but degenerate context arm)

- **p1**: context > psyche > naked > best  (winner context, 5 judgments)
- **p2**: psyche > context > best > naked  (winner psyche, 5 judgments)
- **p3**: naked > best > context > psyche  (winner naked, 5 judgments)
- **p4**: best > context > naked > psyche  (winner best, 5 judgments)
- **p5**: best > psyche > context > naked  (winner best, 5 judgments)

## Cross-vendor judge — gpt-5 (20 judgments)

- Borda: context 36, naked 35, psyche 28, best 21  → **context > naked > psyche > best**
- best > context: **30%**
- best > naked: **30%**
- context > naked: **50%**
- position-first {'B': 5, 'C': 8, 'D': 3, 'A': 4} (uniform≈5) — position-clean
- **gpt-5 agrees `context` leads and is HARSHER on `best` (ranks it last)** — so the shipped `both` under-performing retrieval is not an Opus artifact.

## Verdict

- The **shipped** injection pipeline puts `context` first (does NOT lead with best — retrieval-alone wins).
- This is the FIRST version to test the real artifact end-to-end (all v1-v8 used a reconstruction). It reflects what a user actually gets from the installed MCP.
- **Mechanism**: shipped `both` caps psyche at 40% AND dedups its retrieval against it, so `best` gets THINNER retrieval than the full-budget `context` arm; the 24k psyche is past the useful dose (v5: ~3k core ≈95%) and dilutes vs focused retrieval of the same identity pages. A fixable CONFIG problem, not a refutation of the thesis.
- **Next (v10)**: a rebalanced `both` — small ~3-4k identity core + the FULL retrieval the context arm gets — is the hypothesis to test.

---
_Real prime_context output; Opus generator + judge; small-n (5 tasks). aggregate-v9.py; aggregate only._
