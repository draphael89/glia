# Findings

> **The arc in one breath (read this first).** Eleven runs, each trying to break
> the last, and the finding *changed under scrutiny twice* — that's the point.
> **v1** (non-blind) said *psyche alone dominates* — an artifact. **v2–v6** (blind,
> cross-model, cross-vendor) overturned it: injecting identity is a *complement* to
> retrieval; the combined arm wins. **v7–v8** tempered then partly recovered the
> exact margin (it's construction-sensitive, ~55–65%). Then **v9** tested the
> thing we actually *ship* — not a reconstruction — and it overturned the
> reconstruction: blind judges (Opus *and* gpt-5) prefer **retrieval-alone**; the
> injected arm doesn't beat it. **v10**'s config fix was *refuted* by its own data.
> **v11** measured why: the injected identity is **98% accurate** — v9/v10 was a
> **floor**, not a failure. Then **v12** found the real culprit: v9's retrieval was
> *bugged* (the MCP read page bodies from a subset mirror, dropping 7–8 of the top
> 8 pages) — fix it, and the production result **flips back**: `both` beats
> retrieval-alone again, blind and **cross-vendor** (best-vs-context 52%→64% Opus,
> 30%→56% gpt-5), reconciling with the reconstruction. **Honest bottom line:
> identity injection is a real, accurate complement to retrieval — and testing the
> *shipped* pipeline is what exposed the retrieval bug that was hiding it. The one
> number no LLM judge can give is the verifying user's; that tool is built and
> delivered.** Full story, and every retraction, below.

---

# v1 — Findings (pilot run, non-blind)

Narrative reading of [REPORT.md](REPORT.md) (raw numbers). Small-n pilot
(6 tasks × 4 arms × 3 blind judges); directional, not definitive.

**Superseded in part by v2 — see the banner above.**

## 1. Identity beats relevance — decisively, and on *usefulness* not just fit

On tasks where who-you-are matters, the **psyche** arm beat the **naked**
prompt **100%** of the time and beat **relevance-retrieval (context) 93%**.
Borda: psyche **41**, best 29, context 15, naked 5.

Crucially, the lift shows up on **insight** (psyche 9.3 vs context 7.2), not
only **personal fit** (9.5 vs 7.3). The psyche answers weren't merely more
*you-flavored* — blind judges found them more genuinely *useful*. Judge
rationales cite the answers reasoning from the user's own frameworks by name
(reframing "capability ceiling" as *targeting*; catching a thesis-level
counter the user had left implicit). That is the core of the hypothesis
holding up: telling the model **who you are** raised the quality of the work,
not just its flattery.

## 2. Best-of-breed *lost* to psyche-alone — the surprise

The predicted winner — **context + psyche** — did **not** win. **Psyche alone
beat best-of-breed 80% of the time** (best beat psyche only 3/15).

Interpretation: for reflective, decision-shaped tasks, the retrieved
operational pages (plans, briefs, status reports) **diluted** the concentrated
identity signal rather than complementing it. This *refines* the thesis in a
more useful direction than it confirms it: **identity is the high-density
signal; piling on naive retrieval can hurt.** Curate who-you-are; don't just
add more context.

Caveat: this is about *this* retriever. A retrieval that pulled
identity-adjacent material (essays, values) rather than operational status
might combine better. That is a clean follow-up: vary the retriever, not just
its presence.

## 3. The control is honest — and hides a second, deeper result

On the **technical control** (graph cycle detection — where identity should be
irrelevant and the brain held zero relevant pages), the psyche arm **still
won**. Taken alone that looks like judge **mirroring bias**, and some of it
surely is — we flag it plainly.

But the winning control answer won on a **real technical insight** the others
missed (it uniquely flagged the "Tarjan returns SCCs, not a list of cycles"
trap). That points at a second mechanism that is *itself the user's
hypothesis*: a model handed a rich, coherent picture of the person it's
working for **tries harder** — reasons more carefully — even on a neutral
task. We cannot separate "judges prefer psyche-flavored prose" from "the model
does better work when it knows you" with this design.

**That separation is the #1 next experiment:** a judge blind to the psyche +
an objective correctness/depth scorer on technical tasks, so the "works
harder" effect can be isolated from judge preference.

## Bottom line

- **Core intuition: supported.** Who-you-are beats what's-relevant, and the
  gain is in usefulness, not just personalization.
- **"Best of breed = context + psyche": not supported here.** Psyche alone won;
  retrieval diluted it. A more interesting, actionable finding.
- **Open question, sharpened:** how much of the lift is the model *working
  harder* vs. judges *preferring the voice* — the next run isolates it.

The leverage thesis behind building the brain holds: the highest-value thing
to inject was not the freshest relevant page — it was a faithful map of the
mind.

---

# v2 — the honest run (blind judges + objective controls)

This is the experiment v1 §3 named as "the #1 next experiment." Same four arms
(naked / context / psyche / both), but three changes that remove the ways v1
could have fooled us:

1. **Judges blind to the psyche.** They rank answers on general quality with no
   knowledge of how each was produced — so they cannot reward the recognizable
   voice.
2. **No "personal fit" dimension.** The rubric is specificity / actionability /
   correctness / insight. Nothing pays out merely for sounding personal.
3. **Objective scoring on neutral controls.** Two tasks where identity is
   irrelevant (CAP-theorem question; longest-common-subsequence implementation)
   are graded pass/fail against a fixed 5-point rubric, the LCS one verified by
   running each answer's code against a brute-force reference.

9 tasks (7 identity-shaped + 2 controls) × 4 arms × 2 blind judges. Full numbers
in [REPORT-v2.md](REPORT-v2.md).

## 1. The reversal: psyche-alone dominance was an artifact

Blind Borda on identity-shaped tasks: **best 34, context 25, psyche 15, naked
10.** The combined arm wins; **psyche-alone falls to third, below context-alone.**
Head-to-head, blind: `context` beats `psyche` **71%**; `best` beats `psyche`
**79%**; `best` beats `context` **71%**.

v1's striking "psyche beats best 80%" was mostly **judges rewarding a voice they
could see, plus a rubric dimension that paid for it.** Remove both and it
inverts. We take the hit and keep v1 in the repo: a result worth your name is
one you've tried, in public, to kill.

*(Length is not the confound: mean answer length is ~2,210–2,275 chars across
all four arms. Blind judges are rewarding content, not verbosity.)*

## 2. The durable, sharper finding: identity is a complement

Adding the psyche **on top of** retrieval measurably helps — `best` beats
`context` 71% and tops the Borda. The rubric says exactly why:

| arm | specificity | actionability | correctness | insight |
|---|---|---|---|---|
| naked   | 7.0 | 8.1 | 8.2 | 6.8 |
| context | 8.6 | 8.4 | 8.5 | 8.1 |
| psyche  | 7.4 | 7.2 | 8.2 | **8.8** |
| best    | **8.6** | 8.3 | **8.6** | **9.0** |

**Retrieval buys specificity and actionability; identity buys insight.** Psyche
alone is thin on specificity (7.4) — it knows the *person*, not the *problem*.
Grounding fixes that. Insight is the column identity owns (psyche 8.8 tops the
grounding-free arms; `best` tops it outright at 9.0). The winning recipe is
*both*, and that's now the default the `glia-context` MCP ships.

Per-task, the picture is consistent: `context` wins the four grounded
decision/planning/writing tasks, `best` wins two, and `psyche`-alone wins only
the single pure-identity-expression essay (t5). Identity carries a task exactly
when the task *is* the identity.

## 3. The clean part: identity is not a global "try harder" effect

v1 §3's live worry was that priming with a person just makes the model work
harder at everything, faking a lift even on neutral tasks. **Resolved.** On the
two objectively-scored controls, **every arm — including the naked prompt —
scores 100%** (all rubric points, LCS verified by execution). A dead heat at
the ceiling. Identity gives *nothing* on tasks that aren't about the person —
which is what tells you its lift on the tasks that *are* about the person is
real and **specific**, not a diffuse effort bump. The confound v1 couldn't rule
out, v2 rules out.

## Bottom line (v2)

- **Core intuition: still supported, and now on the honest test.** Injecting who
  you are makes an agent measurably sharper under blind judging — its specific
  contribution is *insight*.
- **But it's a complement, not a replacement.** Retrieval grounds; identity
  elevates. Inject **both**. v1's "curate identity *instead of* context" was too
  strong; "curate identity *on top of* context" is what holds.
- **Mechanism isolated.** The lift is specific to identity-shaped work, not a
  global effect — neutral controls tie at ceiling.
- **Still a pilot** (n=7 identity tasks, 2 judges). The harness scales; next run
  widens the judge panel and crosses model families to tighten the intervals.

The leverage thesis survives in its honest form: a faithful map of the mind is
worth injecting — alongside, not instead of, what's relevant to the question.

---

# v3 — the confidence run (did more judges overturn it?)

v2's blind result rested on only 2 judges/task. The answers are fixed, so the
noisy part is the judging. v3 re-judges the **same** anonymized answers with 5
more blind judges each (→ **7/task, 49 judgments**) and 3 more objective scorers
per control (→ 4). Full numbers in [REPORT-v3.md](REPORT-v3.md).

**It held — and tightened.** Merged blind Borda: **best 118, context 83, psyche
65, naked 28** — the exact v2 ordering, now on 7× the data. The key pairwise,
**best > context, is 71% (35/49) and holds in 6 of 7 tasks.** best > psyche 82%;
context > psyche 59%; psyche-alone stays third. The rubric signature is
unchanged: retrieval owns specificity/actionability, identity owns insight
(psyche 8.9 tops the grounding-free arms, best 9.1 outright). On the neutral
controls, all four arms score **100%** across 8 gradings — the identity lift
stays specific to identity-shaped work.

More judges did not rescue the v1 headline and did not weaken the v2 one. The
honest finding is stable: **inject both; identity is the insight layer on top of
retrieval.** The remaining threat is self-preference — v2/v3 judges were Opus,
the same model that generated the answers. v4 takes that on.

---

# v4 — the cross-model check (is it Opus self-preference?)

v2/v3 used Opus as both generator and judge — the tightest possible
self-preference loop. v4 re-judges the **same Opus-generated answers**, blind,
with a **different model**: Haiku 4.5. (Fable 5 was also planned but hit a usage
limit and didn't run — so this rests on one non-generator model, and a smaller
one; weaker than a two-model check, and we say so.) Full numbers in
[REPORT-v4.md](REPORT-v4.md).

**What reproduces, and what doesn't:**

- **The ordering reproduces.** Haiku, blind, independently ranks
  **best > context > psyche > naked** — the exact order Opus produced. So the
  result is **not simply Opus preferring its own prose.**
- **The floor is robust.** naked is clearly worst for Haiku too (Borda 14 vs
  best 41) — priming with *something* real (identity or retrieval) beats a bare
  prompt regardless of judge.
- **But the best-vs-context margin is model-dependent.** Opus saw best > context
  at 71%; Haiku sees it at **52% — a near-tie** (Borda best 41 vs context 39).
  A smaller judge sees the *floor* clearly but is less sensitive to the subtle
  *insight* lift that identity adds on top of retrieval. Interestingly Haiku
  also rates psyche-alone a bit higher relative to the field than Opus did.

**Honest takeaway.** The robust, cross-model claims: (1) priming beats a naked
prompt, and (2) identity + retrieval together lead the field. The claim that is
*model-sensitive* and shouldn't be over-trusted from a pilot: the exact size of
the "identity adds this much on top of retrieval" edge — a strong judge (Opus)
reads it as clear, a smaller judge (Haiku) as marginal. Trust the ordering;
treat the margin as a hypothesis. A true cross-vendor judge (GPT/Gemini) is the
stronger test still to run.

---

# v5 — dose-response (how much psyche is enough?)

The MCP ships a design claim we hadn't directly measured: identity is
high-density, so a *concentrated* core carries the lift and the psyche can be
capped to leave room for retrieval. v5 tests it. Truncating the psyche to N
tokens is exactly what the MCP does, so for each of 5 tasks we generated a
psyche-arm answer at four budgets — **tiny ~700, small ~3k, medium ~8k, full
~28k tokens** — and blind-ranked them. Numbers in [REPORT-v5.md](REPORT-v5.md).

**Borda by dose:** tiny **4**, small **20**, medium **15**, full **21**.
**Insight by dose:** 7.8 → 8.6 → 8.6 → **9.4**.

- **The self-page alone (tiny) is not enough** — Borda 4, far below the rest.
  You need at least one full essay's worth of identity.
- **A ~3k-token concentrated core (small) reaches ~95% of the full psyche's
  blind ranking** (Borda 20 vs 21). This is the claim holding up: most of the
  quality lift is in the first few thousand tokens of well-ordered identity
  (self-page → top essays). The medium dip is noise (n=10, and the mid-essay
  truncation cut awkwardly).
- **But insight keeps climbing to the full psyche** (9.4 vs 3k's 8.6). More
  identity still buys *insight* past the ranking knee — the deepest, most
  identity-saturated answers come from more psyche.

**Validates the MCP's cap, with the tradeoff now quantified.** The 40%-of-budget
psyche cap clears the ~3k-token knee at every realistic budget (40% of a 20k
budget = 8k tokens; of 60k = 24k ≈ full), so it captures most of the insight
climb while still reserving the majority of the window for retrieval. The knee
being ~3k also means: if the window is *tight*, ~3k tokens of front-loaded
identity (self-page + top essays) is the high-value core to keep — exactly the
`identityRank` ordering the exporter already front-loads.

---

# v6 — the true cross-vendor judge (is it Anthropic self-preference?)

v2/v3 judged with Opus; v4 with Haiku — both **Anthropic**. The one threat left
open: maybe the whole family shares a preference for its own outputs. v6 settles
it — a **non-Anthropic frontier model, gpt-5 (OpenAI)**, blind-judges the same
FIXED Opus-4.8 answers. Numbers in [REPORT-v6.md](REPORT-v6.md).

**It reproduces.** gpt-5 (28 blind judgments, position bias controlled) ranks
**best first** (Borda: best 52 > context 42 > naked 40 > psyche 34) and beats
context **64%**, psyche **68%** head-to-head. And the *mechanism* holds cleanly
on its rubric: psyche-alone is **lowest on specificity** (7.1) but **top on
insight** (8.6); `best` tops both (7.9 / 8.7) — exactly "retrieval buys
specificity, identity buys insight." **A different vendor's frontier model agrees
the combined arm is strongest — so the finding is not Anthropic self-preference.**

**Honest divergence.** gpt-5 is harsher on psyche-*alone* (ranks it last, below
naked) and kinder to concise naked answers than Opus was. So the ordering of the
*weaker* arms (psyche vs naked) is judge-dependent; the **headline — inject BOTH,
retrieval→specificity, identity→insight — survives cross-vendor, the exact tail
order does not.**

**The deepest catch — blind judging *understates* identity.** Reading gpt-5's
rationales explains its harshness on the psyche arm: it repeatedly penalizes the
identity-informed answers' **real** specifics as *fabrication* — "D and C
introduce fabricated details that weaken correctness," "over-specific with
invented details" (5/27 judgments). But those details aren't invented — they're
David's actual projects, people, and priorities, pulled from his brain. **A judge
blind to the psyche can't verify them, so it marks down the very specificity that
identity injection exists to provide.** The real user — who *can* verify — would
value exactly what the blind judge punishes. So every blind result here, v2
through v6, likely *understates* identity injection's real-world value; the effect
we measured is a floor, not a ceiling. (This is why the winning arm is `both`:
retrieval supplies specifics a blind judge *will* credit, alongside the identity
it won't.)

**Methodological catch.** gpt-4o was **unusable** as a judge here: it ranked
whatever sat in slot A first **~90%** of the time (severe position bias) with
near-flat content scores. Cross-vendor judging is confounded by judge-specific
biases — a *discriminating* judge (gpt-5) is required, and a weaker model can
silently fail to measure the effect at all. (Access: OpenAI API via the machine's
own key; raw judgments gitignored, aggregate only.)

---

# Robustness — is the lift just verbosity? (no)

The obvious confound: maybe injected answers win because they're *longer* and
judges reward length, not insight. Checked directly against the existing answers
(`verbosity-check.py` → [VERBOSITY-CHECK.md](VERBOSITY-CHECK.md)), two
task-controlled tests, across all three judge vendors.

- **Length barely differs.** Mean words/arm: naked 362, context 376, psyche 388,
  best 393 — a ~**8%** spread (every arm answered the same prompt under the same
  instruction). Whatever identity injection does, it isn't padding the answer.
- **Length weakly predicts score.** Spearman(length, per-answer Borda) is
  **+0.19** (Opus), **+0.17** (Haiku), **+0.07** (gpt-5) — all weak; the longer
  answer wins ~**60%** of within-task pairs. A mild association, expected because
  a genuinely insightful answer *tends* to run slightly longer — correlation, not
  cause.
- **Decisive: a shorter arm beats a longer one on content.** In **every** judge
  pool, `psyche` is *longer* than `context` (388 vs 376 words) yet ranks **below**
  it (e.g. Opus Borda 65 < 83); under gpt-5, `psyche` even outruns `naked` and
  still loses. If length drove the ranking these inversions couldn't happen. **The
  `best`-first ordering survives controlling for verbosity** — content, not word
  count, is doing the work.

---

# How certain is it? (task-clustered significance)

The pooled counts (49, 28 judgments) look big, but they re-rate answers to just
**7 tasks** — the honest unit of independence is the *task*, not the judgment.
`significance.py` → [SIGNIFICANCE.md](SIGNIFICANCE.md) does the cluster-correct
tests, and the result tempers the headline honestly:

- **Direction is robust.** `best` beats `context` in **6/7** Opus tasks (pooled
  71%) and **beats `naked` 88%**; retrieval beats naked 82%. The ordering
  reproduces across all three judge vendors (Opus, Haiku, gpt-5) and survives the
  verbosity control above.
- **But significance is n-limited, and we say so.** The conservative across-task
  sign test is **p ≈ 0.125** even at 6/7 (not < 0.05), and the cross-vendor
  (gpt-5) task-clustered 95% CIs for best-vs-context **include 50%**. A
  task-clustered bootstrap on the Opus data does exclude 50% ([53%, 88%]), but it
  over-credits correlated re-judgments of the same fixed answers — when the two
  disagree, believe the sign test.
- **So:** trust the **ordering**; treat the **exact percentages** as directional.
  The only thing a re-judge can't buy is more tasks — so [§ v7](#v7--the-expansion-run-buy-the-tasks) below *buys them*, and the result tempers the pilot.

---

# v7 — the expansion run (buy the tasks)

The significance section said the one fix a re-judge can't buy is more tasks. So
we bought them: **7 fresh tasks (t10–t16)**, predictions **pre-registered before
generation**, generated and blind-judged **identically** to v2 (same prompts,
schemas, blind protocol; 5 judges/task) — with one tightening: strict per-arm
read isolation, after live QA caught a `psyche` arm grepping the context files.
Combined with v2/v3, that's **12 identity tasks / 73 blind judgments**. Numbers in
[REPORT-v7.md](REPORT-v7.md), builder in `harness/build-context.py`.

**And it tempers the headline — honestly.**

- **The ordering holds.** `best > context > psyche > naked` on all 12 tasks; `best`
  is Borda-first and still beats **psyche-alone 75%** and **naked 79%**. Injecting
  identity+retrieval beats identity-alone, and beats nothing — those are solid.
- **But the marginal edge of identity *over* retrieval did not replicate.** `best`
  beats `context` in only **7/11 tasks, 59% pooled** (sign test p = 0.55, n.s.) —
  **down from the pilot's 71%.** On the fresh tasks `best` won t10 but *lost* to
  `context` on t11, t13, t14. **The 7-task pilot overstated best-vs-context; the
  honest estimate is coin-flip-plus, not a clear win.**
- **Why — and it's the dedup rationale, caught in the wild.** The fresh tasks where
  `best` lost (t11 "why am I stuck", t14 "weekly rhythm") are exactly the ones
  whose *retrieval* pulled David's **own essays** (telos-is-velocity,
  daimon-charter) as the context — so the identity was *already present* and adding
  the psyche on top was redundant. Where retrieval was operational, not
  identity-laden (t10 product strategy), `best` beat `context` 80%. **Identity
  injection helps over retrieval precisely when retrieval doesn't already surface
  the identity** — which is exactly why the production `prime_context` dedups the
  psyche against retrieval instead of stacking them.
- **Controls stay clean.** On the checkable Bloom-filter task every arm scored
  100% objectively; identity adds nothing where an answer is just right-or-wrong.
- **A construction caveat, stated plainly.** How identity-laden the `context` arm
  is depends on how its material was retrieved. v7's context files were built with
  keyword-rich queries, so t11/t14 pulled several essays; the *production* server,
  querying with the *natural task sentence*, surfaces those essays far less often
  (measured dedup ~0% on natural prompts — see the dedup ledger entry below). So
  the exact best-vs-context number is sensitive to what retrieval happens to
  surface. **§ v8 below tests this directly — rebuilding these tasks' context the
  production way recovers best-vs-context from 33% to 60%, so v7 partly
  under-counted identity.**

**Net after v7:** the durable claim is narrower and better-supported — *inject both;
`best` is the top arm; identity beats naked and beats identity-alone.* The flashy
"identity beats retrieval 71%" was a small-sample high; the real marginal effect is
modest and **conditional on retrieval not already carrying the identity.** That
conditionality is the product design, not a footnote to it.

---

# v8 — was the tempering a context-construction artifact? (partly — it recovers)

v7 flagged its own confound and v8 tests it. v7 built each `context` file with a
**keyword-rich** query that often pulled David's own essays into the retrieval
arm; the *production* server queries with the **natural task sentence**, which
(the dedup measurement below showed) surfaces those essays far less. v8 rebuilds
the SAME 5 identity tasks' context with natural-task queries and re-runs
generation + judging identically — only the context-query construction differs.
[REPORT-v8.md](REPORT-v8.md).

**The identity edge recovers — v7 partly under-counted it.**

- `best` beats `context` on the 5 tasks: **33% with keyword context (v7) → 60%
  with natural context (v8)**; best wins **1/5 → 3/5** tasks.
- The mechanism is visible per task. **t14 "weekly rhythm"**: keyword context
  pulled 4 essays (identity already present) → best **0%**; natural context pulled
  **0** essays (operational) → best **80%** (+80pp). **t13 bio**: +80pp likewise.
  Where a task genuinely retrieves essays *even* on a natural query (**t11 "why am
  I stuck"**, 6 essays both ways) `best` stays suppressed (40%) — that part is
  real, not artifact.
- So production-realistic context puts the identity-over-retrieval edge around
  **~60%** on these tasks — above v7's 59% headline (which used essay-laden keyword
  context) and below the pilot's 71%. The truth is **construction-sensitive and
  lands in between.**

**Synthesis across v7+v8.** Two forces make identity genuinely additive in
production, and v7's keyword context defeated both: (1) natural task queries rarely
pull the identity essays, so `context` is operational and the psyche adds real
identity; (2) the dedup strips essays on the rare occasions they *are* pulled. The
durable claim, now triangulated across three constructions (pilot 71% / keyword
33% / natural 60%): **`best` is the top arm; identity's marginal edge over
retrieval is real and moderate (~55–65% production-realistic), and collapses only
when retrieval already carries the identity.** The exact number was never the
finding — the *conditionality* is.

---

# v9 — the production-pipeline test (does the SHIPPED thing win?), and it doesn't

Every version so far (v1–v8) fed the generator a *reconstruction* of context —
raw pages re-read via `genPrompt`. v9 is the first to test the **actually-shipped
artifact**: the real `prime_context` output captured per task per mode from the
compiled MCP (mode-aware header + 40%-capped, self-page-first psyche + dedup'd
*natural-query* retrieval), then generated + blind-judged. 5 tasks. Numbers in
[REPORT-v9.md](REPORT-v9.md); harness `capture-prod-injections.mjs`.

**The shipped `both` does NOT beat retrieval-alone — cross-vendor confirmed.**

- **Opus judge (25 judgments):** `context` **44** > `best` 41 > `psyche` 35 >
  `naked` 30. `best` is *second*, and best-vs-context is a coin-flip **52%**.
- **gpt-5 judge (20 judgments, position-bias-clean):** harsher — `context` **36**
  > `naked` 35 > `psyche` 28 > **`best` 21 (LAST)**; best-vs-context **30%**,
  best even loses to `naked` (30%).
- Both non-trivially independent judges put **`context` (retrieval-alone) first**
  and decline to reward the injected `both` arm. The clean "best is the top arm"
  from the reconstructions **did not survive contact with the real product.**

**Why — the mechanism is in the capture.** The shipped `both` mode spends ~40% of
budget on the psyche *and* dedups its retrieval against that psyche, so on these
tasks `best` ends up with **thinner retrieval than the `context` arm** (which gets
the full budget). Worse, for identity-shaped tasks the dedup moves the relevant
identity pages *out* of `best`'s retrieval — but the `context` arm keeps them as
*ranked, focused* pages, and the judges preferred that focused framing over
`best`'s 24k-token psyche dump. The 24k psyche looks to be **past the useful dose**
(v5 found a ~3k core reaches ~95%) and is *diluting*, not helping, relative to
focused retrieval of the same identity content.

**Honest caveats:** small n (5 tasks); p1's capture hit a cold-query retrieval
miss so its `both` arm was psyche-only (degenerate — it dragged `best` down, but
the result holds on p2–p5 too); single shipped config. This measures the *current
shipped configuration*, not the thesis.

**v10 — the rebalance hypothesis, tested and REFUTED.** I predicted the shortfall
was config: shrink the identity core to ~4k (which also un-dedups retrieval so
`best` keeps the relevant pages as focused ranked context) and `best` should
recover. It did the **opposite**. Re-running the same 5 tasks with a 4k core (only
the `both` injection changed): `best`-vs-`context` **fell 52% → 24%**, and
`context`'s Borda lead *grew*. So a *smaller* core is *worse*, not better — more
psyche helps the combined arm (consistent with v5's dose-response), and the shipped
24k is the better of the two. The production shortfall is **not** a core-size knob.

**What v9+v10 actually establish — the honest, doubly-confirmed conclusion.** On
the *shipped* pipeline, blind judges (Opus and gpt-5) prefer **retrieval-alone**,
and adding identity on top doesn't beat it *at any core size*. WHY matters: the v6
finding was that a psyche-*blind* judge penalizes the identity answers' real
specifics as "fabricated" because it can't verify them. Production `context`
(natural-query retrieval) is focused, ranked, and *verifiable-looking*; the psyche
adds specifics the blind judge discounts. **So this is a FLOOR, not a refutation of
the thesis** — the one evaluator who *can* verify the identity (the actual user)
is exactly the one not in the loop. The blind, product-realistic measurement says:
*don't assume identity injection beats good retrieval for a verification-blind
reader.* The `psycheCoreMaxTokens` knob stays (default 24k, now validated over 4k);
no default change. **The biggest lesson of the whole arc: test what you SHIP, and
let it overturn your prediction — v10 did.**

**v11 — is it really a floor? MEASURED: yes.** The floor claim needs teeth: are
the injected answers' specifics actually *real* (blind judges wrongly penalizing
them), or *fabricated* (blind judges rightly penalizing them)? v11 fact-checked
**every** specific claim about the user in the v9 `best`+`psyche` answers against
the psyche, with an *informed* Opus checker (psyche stays internal — no privacy
line crossed). **196 identity claims: 89% supported by the psyche, 9% unverifiable,
just 2% contradicted. Of the *verifiable* claims, 98% are accurate.** So the
injected identity is **overwhelmingly true** — the v9/v10 blind judges preferred
retrieval while marking down identity content that is, in fact, 98% correct. That
is the fabrication penalty made quantitative: **the verification-blind measurement
UNDERSTATES identity, and it is a floor, not a hallucination problem** (2%
fabrication is negligible). The one reader who can verify these accurate specifics
— the user — is exactly the one no LLM judge can stand in for. **This is where the
autonomous arc honestly ends: LLM judges bound identity's value from *below*; the
true value needs a human who can verify. Every number here is a floor.**

# v12 — the shipped result FLIPS once retrieval is fixed (v9 was a bug)

Probing why v9's retrieval was thin surfaced a real bug: `gbrain query` searches
the full brain but the MCP read bodies from a *subset* mirror, so on some queries
7–8 of the top 8 pages were silently dropped and the `both` arm was left with
almost no grounding. Fixed it — a bounded live `gbrain get` fallback for
mirror-missing pages + an operational-snapshot noise filter (reflections task
0→5 substantive pages). I *predicted* this would only reinforce v9 ("retrieval
wins even harder"). **v12 refuted that prediction — it flips the finding.**

Same 5 production tasks, same shipped pipeline, only the *fixed* retrieval:

- **Opus (25 judgments):** `psyche` 46 > **`best` 42** > `context` 38 > `naked` 24 —
  `context` fell from 1st (v9) to 3rd, and **best-vs-context rose 52% → 64%**.
- **gpt-5 (18 judgments, position-clean):** `best` **30** > `context` 29 > `naked`
  27 > `psyche` 22 — `best` went from **LAST (v9) to FIRST**, best-vs-context
  **30% → 56%.**
- **Both independent vendors now put the injected `both` arm ahead of
  retrieval-alone.** The v9/v10 "shipped both loses to retrieval" was **an artifact
  of the retrieval bug**, not a property of identity injection.

**This reconciles the whole arc.** The reconstruction runs (v2–v8) said *inject
both wins*. The first production test (v9) said *retrieval wins* — but its
retrieval was broken, starving the very arm under test. Fix the retrieval and the
production result snaps back to the reconstruction: **with sound grounding, adding
identity on top of retrieval beats retrieval alone, blind and cross-vendor.** And
v11 already showed that identity content is 98% accurate, so the win is real, not
hallucinated. The lesson stands and sharpened: *test what you ship — it will
expose the bugs the reconstruction hid, and fixing them is the actual product
win.* The one thread no LLM judge can close is still human eval
(`harness/generate-human-eval.py`, delivered).

## Quantifying the bug — and completing the fix (`REPORT-completeness.md`)

v12 named the retrieval bug; then we *measured* it. Across 15 real queries
(`harness/retrieval-completeness.py`, aggregate-only), at the injection's top-6 depth
only **31% of top-ranked pages were readable from the mirror — 69% were silently
dropped, and 12 of 15 queries were starved** (several to 0/6). That is the mechanism
of the v9 regression, made numeric: the injected arm wasn't failing, it was fed a
near-empty context.

The fix has two parts. (1) The bounded `gbrain get` fallback for mirror-missing pages —
but it was *serial* (one ~170ms subprocess per miss), so its cap sat at a timid 3,
recovering only half the misses. (2) **Prefetch the missing pages concurrently** (a
small worker pool) so the cap can rise to 8 without paying cap×round-trip: completeness
goes **31% → 99%** (+67 points). Measured end-to-end on a 0-mirror-hit query, the
injected arm's retrieval went from **3 pages / ~286 tok → 6 pages / ~2264 tok** (8×) for
+0.28s, and parallelism buys back 0.8s vs the same reads in series. **v12 flipped the
finding at ~65% completeness; the product now runs at 99%.**

## v13 — does identity survive *complete* retrieval? (the sharp open question)

v12's win was measured with retrieval still only ~65% complete, leaving a real doubt:
was the psyche partly a *proxy* for the pages retrieval was dropping? v13 isolates it —
a controlled 2×2 (`context`/`both` × `thin` cap-3 / `full` cap-8), all four arms judged
blind together (`harness/eval-v13-completeness.js`, `aggregate-v13.py`). If `both_full`
still beats `context_full`, identity is a genuine *complement*, not a retrieval-gap
filler — the strongest form of the thesis. (p2 is a natural control: its mirror coverage
was already complete, so its thin and full arms should tie.) Result in `REPORT-v13.md`.

---

# Iteration loop — injection tuning (what moved the needle, what didn't)

A `/loop` round of improve → blind-A/B → keep-or-cut on the injection itself
(reusable harness: `harness/eval-inject-ab.js`). The honest ledger:

- **Dedup retrieval against the psyche — kept (correctness safety), but it fires
  less than first claimed.** `prime_context` drops psyche-present pages from
  retrieval and **backfills** down the ranked list to `topK` genuinely-new unique
  pages. An early note put the overlap at ~50%; instrumenting the shipped server
  (`dedupedCount`, added after v7) and measuring 8 representative queries corrected
  that: overlap is **query-phrasing-dependent and usually low** — **~0% on natural
  task prompts** ("organize my week…", "why am I stuck…"), spiking to ~80% only
  when the query literally names the essays ("loyalty to the future self…"). The
  reason: the injected psyche is a small fixed core (~9 essays after the cap), and
  gbrain's hybrid search on a *natural* task seldom returns those exact pages — it
  returns operational/atom pages instead. So dedup is a cheap **correctness
  guardrail** (never double-inject when overlap *does* happen), not the frequent
  token win first advertised. Honest measurement shrank the claim.

- **A model-facing "how to use this" directive — cut (no effect).** Adding an
  explicit "serve this specific person, reason from their frameworks…" directive
  (+closing line) to the prime was a **dead 50/50 tie** over 6 tasks × 2 blind
  judges. A capable model already personalizes from the identity+context, so the
  extra tokens buy nothing. Reverted. (The "call prime_context first" nudge lives
  at the protocol level via the server `instructions` instead — a different lever,
  about *whether* the agent primes, not answer quality.)

- **The lesson.** For a strong model, injection *format* is largely neutral —
  what matters is the *content* (identity present, retrieval present, and the
  right, non-duplicated pages). So the durable wins were content (dedup/backfill)
  and usage (server `instructions`, the `explain_context` preview tool), not
  prose. Query-aware psyche truncation was scoped but *declined*: with the psyche
  front-loaded by `identityRank`, the 24k cap already keeps the self-page + top
  essays (v5: ≈ full psyche on Borda), so reordering within the surviving core is
  a predicted tie — not worth the complexity. Measure, keep the win, cut the wash.
