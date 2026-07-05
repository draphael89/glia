# Findings — pilot run

Narrative reading of [REPORT.md](REPORT.md) (raw numbers). Small-n pilot
(6 tasks × 4 arms × 3 blind judges); directional, not definitive.

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
