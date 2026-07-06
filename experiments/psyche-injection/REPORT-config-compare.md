# both-mode config comparison — does a focused core recover the combined arm?

| config | Borda order | best>context | best>naked | judgments |
|---|---|---|---|---|
| v9  (24k core, shipped) | context > best > psyche > naked | 52% | 60% | 25 |
| v10 (~4k core, rebalanced) | context > psyche > best > naked | 24% | 60% | 25 |

## Verdict

- **Rebalancing did NOT flip the order** — `best` still doesn't lead `context` (v9 context > best > psyche > naked → v10 context > psyche > best > naked). The shipped both-mode's shortfall isn't just the core size; identity's marginal value over natural-query retrieval is genuinely thin in production. Keep the honest v9 finding.

_Same 5 production tasks; only the both injection differs. compare-configs.py; aggregate only._
