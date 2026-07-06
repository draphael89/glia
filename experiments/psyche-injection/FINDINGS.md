# Findings

> **v2 update (read this first).** The v1 headline below — *"psyche alone beats
> everything; retrieval dilutes identity"* — **did not survive blind judging.**
> We ran the isolation experiment v1 itself called for (judges blind to the
> psyche, personal-fit dimension removed, objective scoring on neutral
> controls). Under those conditions the durable finding is different and, we
> think, better: **identity is a real signal, but a *complement* to relevance,
> not a replacement.** The combined arm wins; psyche-alone falls to third. Full
> corrected story in [§ v2](#v2--the-honest-run-blind-judges--objective-controls)
> below and [REPORT-v2.md](REPORT-v2.md). v1 is kept intact for the arc — the
> correction is the point.

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

# Iteration loop — injection tuning (what moved the needle, what didn't)

A `/loop` round of improve → blind-A/B → keep-or-cut on the injection itself
(reusable harness: `harness/eval-inject-ab.js`). The honest ledger:

- **Dedup retrieval against the psyche — kept (efficiency).** On identity-shaped
  tasks ~**50%** of the top gbrain hits are pages *already in the injected psyche*
  (your starred essays). Re-injecting them is pure waste. `prime_context` now
  drops psyche-present pages from retrieval and **backfills** down the ranked list
  to `topK` genuinely-new unique pages. A strict content-uniqueness / token win.

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
