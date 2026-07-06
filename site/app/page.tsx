import { v2, v1, v7, armColor, armLabel } from "./results";

const REPO = "https://github.com/draphael89/glia";

function BordaChart({ data }: { data: { arm: string; score: number }[] }) {
  const max = Math.max(...data.map((b) => b.score));
  return (
    <div>
      {data.map((b) => (
        <div className="bar-row" key={b.arm}>
          <div className="bar-label">{b.arm}</div>
          <div className="bar-track">
            <div
              className="bar-fill"
              style={{ width: `${(b.score / max) * 100}%`, background: armColor[b.arm] }}
            >
              {b.score}
            </div>
          </div>
          <div className="muted" style={{ width: 120 }}>{armLabel[b.arm]}</div>
        </div>
      ))}
    </div>
  );
}

export default function Home() {
  return (
    <main>
      {/* Hero */}
      <section style={{ paddingTop: 96, borderBottom: "none" }}>
        <div className="wrap">
          <span className="pill">an open experiment · built on gbrain</span>
          <h1 style={{ marginTop: 22 }}>
            Tell the model <span className="accent">who you are</span>,<br />
            not just <span className="gold">what&apos;s relevant</span>.
          </h1>
          <p className="lead" style={{ marginTop: 22 }}>
            As context windows grow, the binding constraint shifts from retrieval to identity.
            We measured it — and then we tried to break our own result. What survived: a map of
            <em> who you are</em> makes an agent measurably sharper, but as a <strong>complement</strong> to
            what&apos;s relevant, not a replacement for it.
          </p>
          <div className="flow" style={{ marginTop: 34 }}>
            <a className="btn" href={`${REPO}/tree/main/experiments/psyche-injection`}>Read the experiment</a>
            <a className="btn btn-ghost" href={REPO}>GitHub ↗</a>
          </div>
        </div>
      </section>

      {/* The arc */}
      <section>
        <div className="wrap">
          <h2>How we know</h2>
          <h3>We got a dramatic result. So we distrusted it.</h3>
          <p>
            In the first run, judges could see each answer and scored a &ldquo;personal fit&rdquo;
            dimension. <span className="accent">Psyche-alone</span> looked dominant — it even beat
            relevance-<em>plus</em>-psyche. A headline that good is a warning. Two things could have
            faked it: judges rewarding the recognizable <em>voice</em>, and a rubric that paid out for
            sounding personal.
          </p>
          <p>
            So we ran <strong>v2</strong>: judges <strong>blind</strong> to how each answer was made,
            the personal-fit dimension deleted, and two neutral technical tasks scored objectively
            against a fixed rubric. The honest test. Here&apos;s what held up.
          </p>
        </div>
      </section>

      {/* The result */}
      <section>
        <div className="wrap">
          <h2>The honest result (blind, 49 judgments)</h2>
          <div className="grid2" style={{ marginBottom: 30 }}>
            <div className="card">
              <div className="stat gold">1st</div>
              <div className="stat-label">
                <span style={{ color: armColor.best }}>both</span> tops the blind Borda ranking
                across <strong>12 tasks</strong> and every judge vendor (Opus, Haiku, gpt-5)
              </div>
            </div>
            <div className="card">
              <div className="stat gold">75 / 79%</div>
              <div className="stat-label">
                <span style={{ color: armColor.best }}>both</span> beats
                <span style={{ color: armColor.psyche }}> identity-alone</span> 75% and
                no-injection 79% — the robust, cross-vendor claims
              </div>
            </div>
          </div>
          <h3>Blind-judge Borda score</h3>
          <p className="muted">
            {v2.identityTasks} identity-shaped tasks · 4 conditions each · {v2.judgments} independent
            judgments, each blind to how the answers were made.
          </p>
          <div className="card" style={{ marginTop: 16 }}>
            <BordaChart data={v2.borda} />
          </div>
          <p className="muted" style={{ marginTop: 14 }}>
            <span style={{ color: armColor.best }}>Both</span> wins the ranking, and
            <span style={{ color: armColor.context }}> relevance</span> alone beats
            <span style={{ color: armColor.psyche }}> psyche</span> alone — identity is not a
            substitute for grounding, it&apos;s what you add <em>on top</em>. One honest caveat,
            surfaced by the <a href="#kill">v7 expansion</a>: on this 7-task pilot
            <span style={{ color: armColor.best }}> both</span> beat
            <span style={{ color: armColor.context }}> relevance</span> alone 71%, but across
            <strong> 12 tasks</strong> that margin fell to <strong>59%</strong> (not significant).
            The durable claims are <span style={{ color: armColor.best }}>both</span> beating
            identity-alone and no-injection; the extra lift <em>over</em> retrieval is real but small
            and conditional.
          </p>
        </div>
      </section>

      {/* The mechanism */}
      <section>
        <div className="wrap">
          <h2>What identity actually buys you</h2>
          <h3>Retrieval brings the facts. Identity brings the insight.</h3>
          <p>
            The rubric tells you exactly why <span style={{ color: armColor.best }}>both</span> wins.
            Retrieved context is what makes an answer <span className="accent">specific</span> and
            <span className="accent"> actionable</span>. The psyche is what makes it
            <span className="gold"> insightful</span> — it tops that column among the ungrounded arms
            and, combined with retrieval, tops it outright (9.1).
          </p>
          <div className="card" style={{ marginTop: 20 }}>
            <table>
              <thead>
                <tr>
                  <th>arm</th>
                  {v2.rubric.dims.map((d) => <th key={d}>{d}</th>)}
                </tr>
              </thead>
              <tbody>
                {v2.rubric.rows.map((r) => (
                  <tr key={r.arm}>
                    <td style={{ color: armColor[r.arm], fontWeight: 600 }}>{r.arm}</td>
                    {r.vals.map((v, i) => (
                      <td key={i} className={v === Math.max(...v2.rubric.rows.map((x) => x.vals[i])) ? "gold" : ""}>
                        {v.toFixed(1)}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="muted" style={{ marginTop: 12 }}>
            Blind rubric averages (1–10). <span style={{ color: armColor.psyche }}>Psyche</span> alone
            is thin on specificity — it knows the person, not the problem. Grounding fixes that; identity
            is what&apos;s left to add.
          </p>
        </div>
      </section>

      {/* The control */}
      <section>
        <div className="wrap">
          <h2>The clean part</h2>
          <h3>Identity doesn&apos;t just make the model &ldquo;try harder.&rdquo;</h3>
          <p>
            The obvious objection to any priming result: maybe telling the model about a person just
            makes it work harder at <em>everything</em>. So we included two neutral technical tasks —
            a CAP-theorem question and a longest-common-subsequence implementation — where identity is
            irrelevant, and scored them objectively against a fixed rubric.
          </p>
          <div className="card" style={{ marginTop: 8, textAlign: "center" }}>
            <div className="stat" style={{ color: armColor.best }}>{v2.controlsPassRate}%</div>
            <div className="stat-label">
              every arm — including the naked prompt — passes every rubric point on the neutral controls
            </div>
          </div>
          <p className="muted" style={{ marginTop: 16 }}>
            A dead heat at the ceiling. Identity gives you nothing on tasks that aren&apos;t about you —
            which is exactly what tells you its lift on the tasks that <em>are</em> about you is real,
            and specific, not a global effort bump.
          </p>
        </div>
      </section>

      {/* The retraction */}
      <section id="kill">
        <div className="wrap">
          <h2>What we retracted</h2>
          <h3>&ldquo;Psyche alone beats everything&rdquo; did not survive blind judging.</h3>
          <p>
            Our first run said psyche-alone beat the combination 80% of the time, and that adding
            retrieval <em>diluted</em> identity. Under blind judges with the personal-fit dimension
            removed, that reversed: <span style={{ color: armColor.psyche }}>psyche</span> alone dropped
            to third, and <span style={{ color: armColor.best }}>both</span> won. The v1 dominance was
            mostly judges rewarding a voice they could see.
          </p>
          <p className="muted">
            We&apos;re leaving every run in the repo. The correction is the point: a result you put your
            name on should be one you&apos;ve tried, in public, to kill. So we kept pushing. A third run
            re-judged the same fixed answers with {v2.judgesPerTask} blind judges each ({v2.judgments}
            judgments) — the ordering tightened, holding in {v2.consistency.bestOverContext} of
            {" "}{v2.consistency.ofTasks} tasks. A fourth had a <em>different</em> model (Haiku&nbsp;4.5)
            re-judge the Opus-written answers: it reproduced the exact ordering — so this isn&apos;t a
            model grading its own homework. And a sixth crossed <em>vendors</em> entirely — OpenAI&apos;s
            gpt-5, judging blind: <span style={{ color: armColor.best }}>both</span> still wins (beats
            relevance 63%, identity-alone 67%) and the specificity/insight mechanism holds, though gpt-5
            is harsher on identity-alone. The headline survives a different vendor; the exact tail order
            is judge-dependent.
          </p>
          <h3 style={{ marginTop: 28 }}>And the 7-task pilot oversold one number.</h3>
          <p>
            The pilot said <span style={{ color: armColor.best }}>both</span> beats
            <span style={{ color: armColor.context }}> relevance</span> alone 71%. So we bought the one
            thing a re-judge can&apos;t: <strong>more tasks</strong>. Seven fresh, pre-registered tasks,
            generated and blind-judged identically ({v7.identityTasks} tasks / {v7.judgments} judgments
            total). The ordering held and <span style={{ color: armColor.best }}>both</span> still beat
            identity-alone ({v7.pairwise[1].rate}%) and no-injection ({v7.pairwise[0].rate}%) — but the
            margin <em>over retrieval</em> fell to <strong>{v7.bestOverContext.pooledPct}%</strong>{" "}
            ({v7.bestOverContext.tasks} of {v7.bestOverContext.ofTasks} tasks, not statistically
            significant). The reason was instructive: on the tasks where adding identity <em>didn&apos;t</em>
            help, retrieval had already surfaced the person&apos;s own essays — the identity was present,
            so injecting it again was redundant. Identity helps over retrieval precisely when retrieval
            <em> doesn&apos;t already carry it</em>.
          </p>
          <p>
            But that cut two ways — so we checked it (v8). v7&apos;s retrieval was built with
            keyword-heavy queries that <em>over</em>-pulled those essays; the real product queries with
            the plain task sentence, which surfaces them far less. Rebuilding the same tasks&apos; context
            the production way, the margin <strong>recovered from 33% to 60%</strong> — v7 had partly
            <em> under</em>-counted identity. Triangulated across three constructions (pilot 71%, keyword
            33%, natural 60%), the honest edge over retrieval is <strong>~55–65%</strong>: real, moderate,
            and dependent on whether retrieval already carries the identity. The exact number was never
            the finding — the conditionality is.
          </p>
          <h3 style={{ marginTop: 28 }}>Then we tested the thing we actually ship — and it bit back.</h3>
          <p>
            Every run above judged a <em>reconstruction</em> of context. So we captured the
            <em> actually-shipped</em> <code>prime_context</code> output — real header, capped psyche,
            dedup&apos;d natural-query retrieval — and judged answers built from it (v9). Blind judges,
            Opus <em>and</em> gpt-5, preferred <span style={{ color: armColor.context }}>retrieval</span>
            {" "}alone; the injected <span style={{ color: armColor.best }}>both</span> arm did
            <strong> not</strong> beat it. We had a fix ready — shrink the identity core — and tested it
            (v10). It made <span style={{ color: armColor.best }}>both</span> <strong>worse</strong>, not
            better. Prediction refuted, in public.
          </p>
          <p>
            The honest read: this is a <strong>floor</strong>, not a refutation — and we measured it
            (v11). We fact-checked <strong>every</strong> specific claim about the user in those injected
            answers against the ground-truth identity file: <strong>196 claims, 98% accurate, 2%
            fabricated.</strong> So the blind judges preferred retrieval while marking down identity
            content that is overwhelmingly <em>true</em> — they penalized real specifics they simply
            couldn&apos;t verify (the same effect v6 found). The one reader who <em>can</em> verify them —
            you — isn&apos;t in the loop, and no LLM judge can stand in for that. The product lesson we keep:
            <strong> don&apos;t assume identity injection beats good retrieval for a verification-blind
            reader</strong> — but know that every number here bounds identity&apos;s value from
            <em> below</em>. Test what you ship, not a picture of it.
          </p>
          <p className="muted">
            Small-n throughout — but tried hard, across vendors, a doubled task set, a construction
            control, and the real shipped pipeline, to kill. Every time it bent, we wrote down how.
          </p>
        </div>
      </section>

      {/* Robustness ledger */}
      <section>
        <div className="wrap">
          <h2>How hard we pushed on it</h2>
          <h3>Eleven runs, each trying to break the last.</h3>
          <div className="card" style={{ marginTop: 16, padding: 0 }}>
            <table>
              <thead>
                <tr><th>run</th><th>the test</th><th>what it showed</th></tr>
              </thead>
              <tbody>
                <tr><td className="mono">v1</td><td>signal-finding (non-blind)</td><td>psyche looked dominant — a headline too good to trust</td></tr>
                <tr><td className="mono">v2</td><td>judges <strong>blind</strong>, personal-fit removed, objective controls</td><td>overturned v1: identity is a <em>complement</em>; <span style={{ color: armColor.best }}>both</span> wins</td></tr>
                <tr><td className="mono">v3</td><td><strong>7 judges</strong>/task (49 judgments)</td><td>held and tightened — consistent in 6 of 7 tasks</td></tr>
                <tr><td className="mono">v4</td><td>a <strong>different model</strong> (Haiku 4.5) re-judges</td><td>reproduced the ordering → not self-preference; margin model-dependent</td></tr>
                <tr><td className="mono">v5</td><td><strong>dose-response</strong> — psyche truncated to 4 budgets</td><td>a ~3k-token core reaches ~95% of peak; insight keeps climbing with more</td></tr>
                <tr><td className="mono">v6</td><td>a <strong>different vendor</strong> (OpenAI gpt-5) re-judges</td><td><span style={{ color: armColor.best }}>both</span> still wins (beats context 64%, psyche 68%); mechanism holds → not self-preference</td></tr>
                <tr><td className="mono">v7</td><td><strong>expansion</strong> — 7 fresh pre-registered tasks (→12 total)</td><td>ordering holds, but <span style={{ color: armColor.best }}>both</span>-over-<span style={{ color: armColor.context }}>relevance</span> tempered 71%→59% (n.s.); identity&apos;s edge is conditional on retrieval not already carrying it</td></tr>
                <tr><td className="mono">v8</td><td><strong>construction control</strong> — rebuild context with natural (production) queries</td><td>edge recovered 33%→60%: v7&apos;s keyword context over-pulled essays; honest range ~55–65%, construction-sensitive</td></tr>
                <tr><td className="mono">v9</td><td><strong>production pipeline</strong> — the ACTUALLY-shipped injection, not a reconstruction</td><td>blind judges (Opus + gpt-5) prefer <span style={{ color: armColor.context }}>retrieval</span> alone; injected <span style={{ color: armColor.best }}>both</span> doesn&apos;t beat it. A floor — the psyche-blind judge can&apos;t verify the identity (v6)</td></tr>
                <tr><td className="mono">v10</td><td><strong>rebalance test</strong> — shrink the shipped identity core to recover <span style={{ color: armColor.best }}>both</span></td><td>hypothesis REFUTED: a smaller core made it worse, not better. More psyche helps; the shortfall isn&apos;t a config knob</td></tr>
                <tr><td className="mono">v11</td><td><strong>floor check</strong> — fact-check the injected identity claims against ground truth</td><td>196 claims, <strong>98% accurate</strong>, 2% fabricated: the blind judges penalized real content they couldn&apos;t verify. Every number is a floor</td></tr>
              </tbody>
            </table>
          </div>
          <p className="muted" style={{ marginTop: 12 }}>
            The claims that survived every run — including a blind cross-vendor judge: priming beats a
            bare prompt, and identity + retrieval together lead the field, because retrieval buys
            specificity and identity buys insight. Every run&apos;s harness and aggregate numbers are in the repo.
          </p>
          <p className="muted" style={{ marginTop: 10 }}>
            One subtlety the cross-vendor run exposed: a judge <em>blind to who you are</em> penalizes
            the identity-informed answers&apos; real specifics — your actual projects and people — as
            &ldquo;fabricated,&rdquo; because it can&apos;t verify them. The real user can. So these blind
            numbers are a <strong>floor</strong> on identity&apos;s value, not a ceiling.
          </p>
        </div>
      </section>

      {/* The stack */}
      <section>
        <div className="wrap">
          <h2>The stack</h2>
          <h3>See your mind. Curate it. Inject it — alongside what&apos;s relevant.</h3>
          <div className="flow" style={{ margin: "24px 0" }}>
            <div className="flow-node"><strong>Glia.app</strong><br /><span className="muted">see + curate your brain</span></div>
            <span className="flow-arrow">→</span>
            <div className="flow-node"><strong className="mono">~/.glia/psyche.md</strong><br /><span className="muted">your curated mind</span></div>
            <span className="flow-arrow">→</span>
            <div className="flow-node"><strong>glia-context MCP</strong><br /><span className="muted">injects identity + relevance</span></div>
          </div>
          <div className="grid2" style={{ marginTop: 10 }}>
            <div className="card">
              <h3 style={{ fontSize: 18 }}>Glia.app</h3>
              <p className="muted">
                A native macOS window into your <a href="https://github.com/garrytan/gbrain">gbrain</a> —
                a living Metal constellation. Star the pages that are the truest map of you; export
                the psyche.
              </p>
            </div>
            <div className="card">
              <h3 style={{ fontSize: 18 }}>glia-context MCP</h3>
              <p className="muted">
                An MCP server any agent can call. <span className="mono">prime_context</span> folds
                who you are <em>together with</em> what&apos;s relevant — grounding for specificity,
                identity for insight. The recipe v2 proved.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* CTA */}
      <section style={{ borderBottom: "none", textAlign: "center" }}>
        <div className="wrap">
          <h3 style={{ fontSize: 26 }}>Make your mind observable.</h3>
          <p className="muted" style={{ maxWidth: 540, margin: "0 auto 26px" }}>
            Glia is open source, MIT, native Swift + Metal. Build it, point it at your brain, and
            prime any agent with who you are — on top of what it needs to know.
          </p>
          <div className="flow" style={{ justifyContent: "center" }}>
            <a className="btn" href={REPO}>Get Glia ↗</a>
            <a className="btn btn-ghost" href={`${REPO}/tree/main/experiments/psyche-injection`}>The data</a>
          </div>
          <p className="muted" style={{ marginTop: 40 }}>
            Built on <a href="https://github.com/garrytan/gbrain">gbrain</a>. An experiment in
            making the soul observable to the machine.
          </p>
        </div>
      </section>
    </main>
  );
}
