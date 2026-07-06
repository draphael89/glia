#!/usr/bin/env python3
"""Generate a self-contained, LOCAL human-eval page from the v9 production answers.
v11 proved every LLM-judge number is a FLOOR — the injected identity is 98%
accurate but a blind model can't verify it. The one evaluator who CAN verify is
the user. This builds the tool for that definitive test: David ranks the 4 answers
per task (blind to which arm is which — deterministically shuffled), and the page
computes the human Borda + best-vs-context once he submits.

Output: human-eval.html (gitignored — embeds private answers). Open it in a browser.
"""
import json, os, html

base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONDS = ["naked", "context", "psyche", "best"]
# fixed per-task shuffles (arm -> slot), balanced so no arm sits in one slot
PERMS = [[0, 1, 2, 3], [3, 2, 1, 0], [1, 3, 0, 2], [2, 0, 3, 1], [0, 2, 1, 3]]

data = json.load(open(os.path.join(base, "results/raw/results-v9.json")))
tasks_js = []
blocks = []
for ti, t in enumerate(data):
    perm = PERMS[ti % len(PERMS)]
    # slot k shows arm CONDS[perm[k]]
    slot_arm = [CONDS[perm[k]] for k in range(4)]
    tasks_js.append({"id": t["taskId"], "slotArm": slot_arm})
    cards = []
    for k in range(4):
        arm = slot_arm[k]
        ans = html.escape(t["responses"][arm]).replace("\n", "<br>")
        letter = "ABCD"[k]
        cards.append(f"""<div class="card"><div class="cardhdr">Answer {letter}
          <select data-task="{ti}" data-slot="{k}"><option value="">rank…</option>
          <option>1</option><option>2</option><option>3</option><option>4</option></select></div>
          <div class="ans">{ans}</div></div>""")
    blocks.append(f"""<section class="task"><h2>Task {ti+1}</h2>
      <p class="prompt">{html.escape(t['prompt'])}</p>
      <div class="cards">{''.join(cards)}</div></section>""")

page = f"""<!doctype html><html><head><meta charset="utf-8"><title>Glia psyche-injection — human eval</title>
<style>
  body{{font:15px/1.6 -apple-system,system-ui,sans-serif;max-width:900px;margin:2rem auto;padding:0 1rem;color:#111;background:#fafafa}}
  h1{{font-size:20px}} .prompt{{color:#444;font-style:italic;background:#fff;padding:.6rem .9rem;border-radius:8px;border:1px solid #eee}}
  .cards{{display:grid;gap:12px;margin:12px 0}} .card{{background:#fff;border:1px solid #e5e5e5;border-radius:10px;padding:12px 14px}}
  .cardhdr{{display:flex;justify-content:space-between;align-items:center;font-weight:600;margin-bottom:8px}}
  select{{font:14px sans-serif;padding:3px 6px;border-radius:6px}} .ans{{font-size:14px;color:#222}}
  .task{{margin:26px 0;padding-bottom:8px;border-bottom:2px solid #eee}}
  button{{font:16px sans-serif;padding:10px 22px;background:#111;color:#fff;border:none;border-radius:8px;cursor:pointer;margin:1rem 0}}
  #result{{background:#111;color:#eee;padding:1rem 1.2rem;border-radius:10px;white-space:pre-wrap;font:13px ui-monospace,monospace;margin-top:1rem}}
  .note{{color:#666;font-size:13px}}
</style></head><body>
<h1>Human eval — you can verify your own identity, the LLM judges can't</h1>
<p class="note">Rank the 4 answers per task, 1 (best) to 4 (worst), on how well they'd actually serve <b>you</b>.
You're the only judge who can tell whether the specific claims are true. Which arm is which is hidden until you submit.</p>
{''.join(blocks)}
<button onclick="score()">Score my rankings</button>
<div id="result"></div>
<script>
const TASKS = {json.dumps(tasks_js)};
const CONDS = {json.dumps(CONDS)};
function score(){{
  const borda={{naked:0,context:0,psyche:0,best:0}};
  const pw={{}}, pt={{}}; let n=0;
  for(let ti=0; ti<TASKS.length; ti++){{
    const ranks={{}};
    let ok=true;
    for(let k=0;k<4;k++){{
      const v=document.querySelector(`select[data-task="${{ti}}"][data-slot="${{k}}"]`).value;
      if(!v){{ok=false;break}} ranks[k]=parseInt(v);
    }}
    const used=Object.values(ranks).sort().join('');
    if(!ok||used!=='1234'){{document.getElementById('result').textContent=`Task ${{ti+1}}: give each answer a distinct rank 1–4.`;return}}
    // slot -> arm; rank 1..4 -> borda 3..0
    n++;
    for(let k=0;k<4;k++){{ const arm=TASKS[ti].slotArm[k]; borda[arm]+=(4-ranks[k]); }}
    // pairwise
    for(let a=0;a<4;a++)for(let b=0;b<4;b++){{ if(a===b)continue;
      const A=TASKS[ti].slotArm[a],B=TASKS[ti].slotArm[b];
      if(ranks[a]<ranks[b]){{ pt[A+'>'+B]=(pt[A+'>'+B]||0)+1; pw[A+'>'+B]=(pw[A+'>'+B]||0)+1; }}
    }}
  }}
  const order=[...CONDS].sort((x,y)=>borda[y]-borda[x]);
  const pct=(a,b)=>{{const w=pw[a+'>'+b]||0,l=pw[b+'>'+a]||0;return (w+l)?Math.round(100*w/(w+l))+'%':'-';}};
  let out=`YOUR human ranking (${{n}} tasks)\\n`;
  out+='Borda: '+order.map(c=>c+' '+borda[c]).join(', ')+'  →  '+order.join(' > ')+'\\n\\n';
  out+='best (both)   > context (retrieval): '+pct('best','context')+'\\n';
  out+='best (both)   > naked:               '+pct('best','naked')+'\\n';
  out+='psyche        > naked:               '+pct('psyche','naked')+'\\n\\n';
  out+='Compare to the LLM judges (v9): both they preferred CONTEXT and did NOT reward best.\\n';
  out+='If YOUR ranking puts best/psyche ahead, that is the floor lifting — the value only you can see.';
  document.getElementById('result').textContent=out;
}}
</script></body></html>"""

dest = os.path.join(base, "human-eval.html")
open(dest, "w").write(page)
print(f"wrote {dest} — open it in a browser, rank each task, hit Score.")
