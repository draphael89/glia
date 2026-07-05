import { pilot, armColor } from "./results";

const REPO = "https://github.com/draphael89/glia";

function BordaChart() {
  const max = Math.max(...pilot.borda.map((b) => b.score));
  return (
    <div>
      {pilot.borda.map((b) => (
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
          <div className="muted" style={{ width: 110 }}>{b.label}</div>
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
            We measured it: injecting a map of your mind beats injecting the pages relevant to
            your question — and wins on <em>insight</em>, not just personal fit.
          </p>
          <div className="flow" style={{ marginTop: 34 }}>
            <a className="btn" href={`${REPO}/tree/main/experiments/psyche-injection`}>Read the experiment</a>
            <a className="btn btn-ghost" href={REPO}>GitHub ↗</a>
          </div>
        </div>
      </section>

      {/* The result */}
      <section>
        <div className="wrap">
          <h2>The headline result</h2>
          <div className="grid2" style={{ marginBottom: 30 }}>
            <div className="card">
              <div className="stat accent">100%</div>
              <div className="stat-label">
                psyche-primed answers beat a naked prompt, judged blind
              </div>
            </div>
            <div className="card">
              <div className="stat accent">93%</div>
              <div className="stat-label">
                psyche beats gbrain-style relevance retrieval on identity-shaped tasks
              </div>
            </div>
          </div>
          <h3>Blind-judge Borda score</h3>
          <p className="muted">
            {pilot.tasks} tasks · 4 conditions each · {pilot.judgesPerTask} independent judges per task,
            each blind to how the answers were made.
          </p>
          <div className="card" style={{ marginTop: 16 }}>
            <BordaChart />
          </div>
        </div>
      </section>

      {/* The surprise */}
      <section>
        <div className="wrap">
          <h2>The surprise</h2>
          <h3>More context isn&apos;t better. Identity is the high-density signal.</h3>
          <p>
            We expected <span style={{ color: armColor.best }}>both</span> (relevance + psyche) to
            win. It didn&apos;t. <span className="accent">Psyche alone</span> beat the combination
            80% of the time — the retrieved operational pages <em>diluted</em> the concentrated
            identity signal.
          </p>
          <p>
            The lesson isn&apos;t &ldquo;add more context.&rdquo; It&apos;s <strong>curate who you
            are</strong>. That&apos;s what Glia is for.
          </p>
          <div className="card" style={{ marginTop: 20 }}>
            <table>
              <thead>
                <tr>
                  <th>arm</th>
                  {pilot.rubric.dims.map((d) => <th key={d}>{d}</th>)}
                </tr>
              </thead>
              <tbody>
                {pilot.rubric.rows.map((r) => (
                  <tr key={r.arm}>
                    <td style={{ color: armColor[r.arm], fontWeight: 600 }}>{r.arm}</td>
                    {r.vals.map((v, i) => (
                      <td key={i} className={v === Math.max(...pilot.rubric.rows.map((x) => x.vals[i])) ? "gold" : ""}>
                        {v.toFixed(1)}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="muted" style={{ marginTop: 12 }}>
            Rubric averages (1–10). Psyche wins on <span className="accent">insight</span> (9.3),
            not merely personal fit — the model does better <em>work</em> when it knows who it&apos;s for.
          </p>
        </div>
      </section>

      {/* The stack */}
      <section>
        <div className="wrap">
          <h2>The stack</h2>
          <h3>See your mind. Curate it. Inject it anywhere.</h3>
          <div className="flow" style={{ margin: "24px 0" }}>
            <div className="flow-node"><strong>Glia.app</strong><br /><span className="muted">see + curate your brain</span></div>
            <span className="flow-arrow">→</span>
            <div className="flow-node"><strong className="mono">~/.glia/psyche.md</strong><br /><span className="muted">your curated mind</span></div>
            <span className="flow-arrow">→</span>
            <div className="flow-node"><strong>glia-context MCP</strong><br /><span className="muted">injects it at session start</span></div>
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
                in who you are + what&apos;s relevant, front-loading identity. The beseech-the-god layer.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Honesty */}
      <section>
        <div className="wrap">
          <h2>What we&apos;re not sure of yet</h2>
          <p>
            This is a signal-finding pilot, not a benchmark. On a purely technical control (where
            identity is irrelevant), psyche still won — partly judge bias toward the voice, partly
            (the winning answers suggest) the model simply <em>trying harder</em> when it knows who
            it&apos;s working for. Separating those is the next experiment: judges blind to the
            psyche, plus objective correctness scoring. The harness is built to scale.
          </p>
          <p className="muted">Full methodology, threats to validity, and reproduction steps in the repo.</p>
        </div>
      </section>

      {/* CTA */}
      <section style={{ borderBottom: "none", textAlign: "center" }}>
        <div className="wrap">
          <h3 style={{ fontSize: 26 }}>Make your mind observable.</h3>
          <p className="muted" style={{ maxWidth: 520, margin: "0 auto 26px" }}>
            Glia is open source, MIT, native Swift + Metal. Build it, point it at your brain, and
            prime any agent with who you are.
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
