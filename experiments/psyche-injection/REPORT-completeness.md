# Retrieval completeness — measuring the bug that drove the v9→v12 flip

The v9→v12 arc turned on a claim: the injected `both` arm lost to retrieval-alone in
v9 **because of a retrieval bug**, not because identity injection doesn't help. The
server ranked pages against the whole brain (`gbrain query`) but read page *bodies*
from a local mirror dir (`~/.gbrain/source-default`) that is only a **subset** of the
brain — so top-ranked pages were silently dropped and the injected arm was fed a thin,
holey context. This report **measures** that bug directly, and the fix.

Method: `harness/retrieval-completeness.py` — 15 real queries spanning identity/values,
work/meetings, product strategy, and technical judgment. For each query's top-K ranked
slugs it records whether the body is present in the mirror (readable for free) or
absent (**starved** under the old mirror-only path), then checks whether the bounded
live `gbrain get <slug>` fallback recovers it. Aggregates only; no brain content leaves
the machine (per-query raw is gitignored).

## The bug was large

**Top-6 (the injection's actual retrieval depth), 15 queries, 86 pages examined:**

| | pages | % of top-6 |
|---|---|---|
| present in mirror (free) | 27 | **31%** |
| **missing from mirror** (starved mirror-only) | 59 | **69%** |
| readable **before** (mirror-only) | 27 | **31%** |
| readable **after** (mirror + fallback) | 85 | **99%** |

**+67 percentage points** of completeness. **12 of 15 queries** had ≤ 3 of their top-6
pages readable under the mirror-only path — several had **zero** (e.g. hiring,
personalization, delegation, AI-reflection: 0/6 mirror hits). That is exactly the
starvation that made v9's injected arm look weak: it wasn't identity failing to help,
it was the identity arm being handed a near-empty context. (At top-8 the numbers are
the same story: 71% missing, 29% → 99%, +70 points, 13/15 starved.)

## The fix: a bounded, *parallel* live-read fallback

For up to `GBRAIN_GET_FALLBACK_MAX` top-ranked pages absent from the mirror, read them
live from the full brain. The subtlety is latency: each `gbrain get` is a ~170ms
subprocess, so a serial fallback would add `cap × 170ms`. That's why the cap originally
sat at a timid **3** — which recovers only *half* the misses (top-6: 58/59 needs cap 6;
cap 3 leaves ~30 dropped).

The fix decouples the cap from latency by **prefetching the missing pages concurrently**
(a small worker pool, `GBRAIN_GET_CONCURRENCY=4`) before the accumulation loop, which
then reads bodies from the prefetched map and keeps its relevance-floor / dedup / topK
decisions byte-identical. With the round-trips overlapped, the cap can be generous
(now **8**) for near-complete retrieval at roughly one batch of latency.

**Measured end-to-end** (`--explain`, query with 0 mirror hits, incl. node cold start):

| config | pages | retrieval tokens | wall |
|---|---|---|---|
| old: cap 3, serial (shipped before) | 3 | ~286 | 1.28s |
| new: cap 8, **serial** (concurrency 1) | 6 | ~2264 | 2.36s |
| new: cap 8, **parallel** (concurrency 4) | **6** | **~2264** | **1.56s** |

The injected arm now receives **8× the retrieval content** (286 → 2264 tokens, the full
top-6 instead of a starved half) for **+0.28s** over the old thin path — and parallelism
buys back **0.8s** versus doing the same eight reads in series.

## Why this is the load-bearing result

Every "identity helps / doesn't help" number in this repo is downstream of *what
context the arms actually received*. v9 measured the shipped pipeline and found the
injected arm losing — and this is the mechanism: it was being starved 69% of its
context. Fixing retrieval completeness is what let **v12 flip the finding back**
(`both` beats retrieval-alone again, cross-vendor). The lesson the project values most,
made quantitative: **test what you ship — the reconstruction hid a bug that only the
end-to-end pipeline exposed, and fixing it was the actual win.**

Reproduce: `python3 harness/retrieval-completeness.py`
(`TOP_K=8`, `GBRAIN_GET_FALLBACK_MAX=…` to sweep the cap).
