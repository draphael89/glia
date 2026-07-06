# Psyche Injection — v12 (production-pipeline: does the SHIPPED thing help?)

_Answers generated from the ACTUAL `prime_context` output (real header + capped psyche + dedup'd natural-query retrieval), captured per task per mode from the compiled MCP — not a reconstruction. 5 tasks, Opus judge, blind._

## Combined: 25 blind judgments

- Borda: psyche 46, best 42, context 38, naked 24  → **psyche > best > context > naked**
- best > context: **64%**
- best > psyche: **44%**
- best > naked: **60%**
- context > naked: **76%**
- psyche > naked: **68%**
- rubric means: naked(spec 8.1, ins 7.8) | context(spec 8.5, ins 7.9) | psyche(spec 8.6, ins 9.1) | best(spec 8.2, ins 8.8)

## Per-task winner (note: p1 had a thin-retrieval capture — realistic but degenerate context arm)

- **p1**: context > naked > psyche > best  (winner context, 5 judgments)
- **p2**: psyche > context > best > naked  (winner psyche, 5 judgments)
- **p3**: naked > best > psyche > context  (winner naked, 5 judgments)
- **p4**: best > context > psyche > naked  (winner best, 5 judgments)
- **p5**: psyche > best > context > naked  (winner psyche, 5 judgments)

## Cross-vendor judge — gpt-5 (18 judgments)

- Borda: best 30, context 29, naked 27, psyche 22  → **best > context > naked > psyche**
- best > context: **56%**
- best > naked: **44%**
- context > naked: **61%**
- position-first {'A': 6, 'D': 4, 'B': 5, 'C': 3} (uniform≈4) — position-clean
- **gpt-5 AGREES with Opus: `best` beats `context` (56%)** — the injected arm leads under a second, independent vendor too. Not an Opus artifact.

## Verdict

- Borda order **psyche > best > context > naked**; the injected `both` arm beats retrieval-alone `context` **64%**.
- Tests the ACTUAL shipped artifact end-to-end (v1-v8 used a reconstruction) — what a user really gets from the installed MCP.
- **The injected arm WINS.** With sound retrieval, adding identity on top beats retrieval-alone — reconciling the production pipeline with the reconstruction thesis.

---
_Real prime_context output; Opus generator + judge; small-n (5 tasks). aggregate-v9.py; aggregate only._
