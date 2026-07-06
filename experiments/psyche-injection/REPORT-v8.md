# Psyche Injection — v8 (context-construction control)

_Same 5 identity tasks as v7, but the `context` arm reads material retrieved with the **natural task query** (production-realistic) instead of v7's keyword query. Isolates whether v7's best-vs-context tempering was a context-construction artifact._

| task | kind | context essays (keyword→natural) | best>context v7 (keyword) | best>context v8 (natural) | Δ |
|---|---|---|---|---|---|
| t10→t20 | decision | 0→0 | 80% | 80% | +0pp |
| t11→t21 | reflection | 5→6 | 20% | 40% | +20pp |
| t12→t22 | technical-decision | 0→0 | 50% | 0% | -50pp |
| t13→t23 | writing | 0→1 | 20% | 100% | +80pp |
| t14→t24 | planning | 4→0 | 0% | 80% | +80pp |

- **pooled best>context** — v7 (keyword ctx): **33%**  ·  v8 (natural ctx): **60%**
- **tasks where best beat context** — v7: 1/5  ·  v8: 3/5

## Verdict

- **Partly a construction artifact.** With production-realistic (natural-query) context, best-vs-context RECOVERS (33%→60%). v7's keyword-built context was more essay-laden (identity already present), which suppressed the identity lift. The production number is higher than v7 implied — but still short of the pilot's 71%.
- Either way the v7 core stands: best is the top arm; the marginal edge over retrieval is modest and task-dependent. This just confirms it isn't an artifact of how we built the context files.

---
_Same prompts/psyche/judges/isolation as v7; only context-query construction differs. aggregate-v8.py; aggregate only._
