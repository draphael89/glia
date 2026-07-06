export const meta = {
  name: 'psyche-injection-eval-v17',
  description: 'Does v16 task-shape finding REPLICATE on fresh tasks? 8 new tasks pre-classified generative (synthesis-from-self) vs diagnostic (fact-lookup), variance-reduced (K=3 gens/arm) blind pairwise both-vs-context at complete retrieval. Prediction: generative favors both, diagnostic favors context.',
  phases: [
    { title: 'Generate', detail: '8 tasks × 2 arms × 3 gens (full-retrieval)' },
    { title: 'JudgePairwise', detail: '3 blind judges per (task, round)' },
  ],
}

const MATDIR = '/Users/david/glia/experiments/psyche-injection/materials'
const ARM_FILE = { context: 'context-full', both: 'both-full' }
const K = 3
const NJUDGES = 3

const PAIR_SCHEMA = {
  type: 'object',
  properties: {
    winner: { type: 'string', enum: ['A', 'B'] },
    margin: { type: 'string', enum: ['clear', 'slight', 'toss-up'] },
    reason: { type: 'string' },
  },
  required: ['winner', 'margin', 'reason'],
}

function genPrompt(task, arm) {
  return `You are answering on behalf of David. Produce the single best possible answer FOR HIM specifically. Read ONLY this one file: ${MATDIR}/${task.id}-${ARM_FILE[arm]}.md — it is the context glia-context primed into your session. Use it to serve David specifically. CRITICAL: read EXACTLY that one file and NOTHING else — do NOT list directories, grep, or open any other file.

TASK: ${task.prompt}

Write the ideal answer: concrete, honest, genuinely useful, ~250-450 words. Output ONLY the answer text.`
}

function judgePrompt(task, ctxAns, bothAns, bothFirst) {
  const A = bothFirst ? bothAns : ctxAns
  const B = bothFirst ? ctxAns : bothAns
  return `Two answers to the same task. You do NOT know how either was produced; their A/B order is random. Judge PURELY on which would better serve the person who asked — specificity, actionability, correctness, and genuine insight. Do not reward length or confident filler.

TASK: ${task.prompt}

--- ANSWER A ---
${A}

--- ANSWER B ---
${B}

Pick the better answer, rate the margin, give a one-sentence reason. Return JSON {winner, margin, reason}.`
}

async function runTask(task, tIdx) {
  const rounds = await parallel(Array.from({ length: K }, (_, r) => async () => {
    const [ctxAns, bothAns] = await Promise.all([
      agent(genPrompt(task, 'context'), { label: `gen:${task.id}:ctx:r${r}`, phase: 'Generate' }),
      agent(genPrompt(task, 'both'), { label: `gen:${task.id}:both:r${r}`, phase: 'Generate' }),
    ])
    if (!ctxAns || !bothAns) return null
    const votes = await parallel(Array.from({ length: NJUDGES }, (_, j) => () => {
      const bothFirst = (tIdx + r + j) % 2 === 0
      return agent(judgePrompt(task, ctxAns, bothAns, bothFirst),
        { label: `judge:${task.id}:r${r}:j${j}`, phase: 'JudgePairwise', schema: PAIR_SCHEMA })
        .then((v) => v ? { bothWon: bothFirst ? v.winner === 'A' : v.winner === 'B', margin: v.margin } : null)
    }))
    return { round: r, votes: votes.filter(Boolean) }
  }))
  return { taskId: task.id, type: task.type, prompt: task.prompt, rounds: rounds.filter(Boolean) }
}

const TASKS = [
  { id: 'g1', type: 'generative', prompt: "Write my one-sentence personal mission statement, in my own voice — something true to what I'm actually about." },
  { id: 'g2', type: 'generative', prompt: "Draft the opening 3 sentences of a talk I'd give about what I'm building and why it matters to me." },
  { id: 'g3', type: 'generative', prompt: "Design the shape of my ideal working day — a structure that fits how I actually operate and what I value, not a generic productivity template." },
  { id: 'g4', type: 'generative', prompt: "Write me a short personal manifesto (3–4 sentences) I could pin above my desk to keep me pointed at what matters." },
  { id: 'd1', type: 'diagnostic', prompt: "What did we decide about the NIL product MVP — the contracts, asset generation, and monitoring? Just the decisions." },
  { id: 'd2', type: 'diagnostic', prompt: "Summarize the key points from my recent meetings about the creative pipeline and performance review." },
  { id: 'd3', type: 'diagnostic', prompt: "What are the open questions or product risks around the Reflections knowledge graph, per my notes?" },
  { id: 'd4', type: 'diagnostic', prompt: "According to my notes, how should deterministic gates and AI judgment divide the work in a recommendation system? Give me the recorded reasoning." },
]

const results = await parallel(TASKS.map((t, i) => () => runTask(t, i)))
return results.filter(Boolean)
