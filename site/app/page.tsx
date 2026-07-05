import { v2, v1, armColor, armLabel } from "./results";

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
              <div className="stat gold">71%</div>
              <div className="stat-label">
                adding <span className="accent">who you are</span> to what&apos;s relevant beats
                relevance alone, judged blind
              </div>
            </div>
            <div className="card">
              <div className="stat gold">1st</div>
              <div className="stat-label">
                <span style={{ color: armColor.best }}>both</span> tops the blind Borda ranking
                <em> and</em> every rubric dimension
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
            <span style={{ color: armColor.best }}>Both</span> wins — and it holds:
            <span style={{ color: armColor.best }}> both</span> beats <span style={{ color: armColor.context }}>relevance</span> alone
            in {v2.consistency.bestOverContext} of {v2.consistency.ofTasks} tasks (71% pairwise), and
            <span style={{ color: armColor.context }}> relevance</span> alone still beats
            <span style={{ color: armColor.psyche }}> psyche</span> alone. Identity is not a substitute
            for grounding — it&apos;s what you add <em>on top</em>.
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
      <section>
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
            We&apos;re leaving both runs in the repo. The correction is the point: a result you put your
            name on should be one you&apos;ve tried, in public, to kill. And we pushed on it: a third run
            re-judged the same fixed answers with {v2.judgesPerTask} blind judges each ({v2.judgments}
            judgments) — the ordering didn&apos;t just hold, it tightened, staying consistent in
            {" "}{v2.consistency.bestOverContext} of {v2.consistency.ofTasks} tasks. Still a small-n pilot;
            the open next step is cross-model-family judges.
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
