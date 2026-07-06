export const meta = {
  name: 'psyche-injection-eval-v13',
  description: 'Controlled test of retrieval COMPLETENESS × identity: 4 arms = context/both × thin(cap3)/full(cap8) retrieval, blind-judged. Answers whether identity still helps once retrieval is complete (the sharp test the v12 flip left open).',
  phases: [
    { title: 'Generate', detail: '5 tasks x 4 arms (thin/full × context/both)' },
    { title: 'JudgeBlind', detail: '5 judges/task, blind' },
  ],
}

const MATDIR = '/Users/david/glia/experiments/psyche-injection/materials'
// The 4 arms isolate ONE variable at a time. context_* = retrieval only; both_* =
// retrieval + psyche. *_thin = cap-3 (starved) retrieval; *_full = cap-8 (99%) retrieval.
const CONDITIONS = ['context_thin', 'context_full', 'both_thin', 'both_full']
const ARM_FILE = {
  context_thin: 'context-thin', context_full: 'context-full',
  both_thin: 'both-thin', both_full: 'both-full',
}
const PERMS = [[0,1,2,3],[3,2,1,0],[1,3,0,2],[2,0,3,1],[0,2,1,3],[3,1,2,0]]
const LETTERS = ['A','B','C','D']
const NJUDGES = 5

const BLIND_SCORE = { type:'object', properties:{
  specificity:{type:'number'}, actionability:{type:'number'},
  correctness:{type:'number'}, insight:{type:'number'} },
  required:['specificity','actionability','correctness','insight'] }
const BLIND_JUDGE_SCHEMA = { type:'object', properties:{
  ranking:{ type:'array', items:{ type:'string', enum:['A','B','C','D'] }, minItems:4, maxItems:4 },
  scores:{ type:'object', properties:{ A:BLIND_SCORE, B:BLIND_SCORE, C:BLIND_SCORE, D:BLIND_SCORE }, required:['A','B','C','D'] },
  rationale:{ type:'string' } },
  required:['ranking','scores','rationale'] }

// Identical generation contract to v9 — only the injected file differs per arm, so
// the ONLY thing that varies across arms is retrieval completeness and/or the psyche.
function genPrompt(task, cond) {
  const reads = `Read ONLY this one file: ${MATDIR}/${task.id}-${ARM_FILE[cond]}.md — it is the context glia-context primed into your session (who David is and/or what's relevant). Use it to serve David specifically. CRITICAL: read EXACTLY that one file and NOTHING else — do NOT list directories, grep, or open any other file.`
  return `You are answering on behalf of David. Produce the single best possible answer FOR HIM specifically. ${reads}

TASK: ${task.prompt}

Write the ideal answer: concrete, honest, genuinely useful, ~250-450 words. Output ONLY the answer text.`
}

function blindJudgePrompt(task, responses, permIdx) {
  const perm = PERMS[permIdx]
  let block = ''
  for (let k = 0; k < 4; k++) block += `\n--- ANSWER ${LETTERS[k]} ---\n${responses[perm[k]]}\n`
  return `Evaluate four answers to the same task. You do NOT know anything about who requested them or how each was produced. Judge PURELY on general quality: specificity, actionability, correctness/soundness, and genuine insight/usefulness. Do not reward verbosity or confident-sounding filler.

TASK: ${task.prompt}
${block}
Rank best-to-worst, give per-answer rubric scores (1-10), and a 2-sentence rationale.`
}

async function runTask(task, tIdx) {
  const responses = await parallel(
    CONDITIONS.map((c) => () => agent(genPrompt(task, c),
      { label: `gen:${task.id}:${c}`, phase: 'Generate' })))
  if (responses.some((r) => !r)) return null

  const blind = await parallel(Array.from({length: NJUDGES}, (_, j) => () => {
    const permIdx = (tIdx * NJUDGES + j) % PERMS.length
    return agent(blindJudgePrompt(task, responses, permIdx),
      { label: `blind:${task.id}:j${j}`, phase: 'JudgeBlind', schema: BLIND_JUDGE_SCHEMA })
      .then((r) => r && r.ranking ? { permIdx, ranking: r.ranking, scores: r.scores, rationale: r.rationale } : null)
  }))

  const resObj = {}; CONDITIONS.forEach((c, ci) => { resObj[c] = responses[ci] })
  return { taskId: task.id, kind: 'completeness', prompt: task.prompt, conditions: CONDITIONS,
           responses: resObj, blindJudgments: blind.filter(Boolean) }
}

const TASKS = [
  { id: 'p1', prompt: "I keep splitting focus between Glia (the open-source brain viewer) and the core Reflections product. Should I fold them into one public narrative, or keep them as two separate things? Decide for me and justify the call in terms of what actually matters to me." },
  { id: 'p2', prompt: "Be honest with me: what is the single most likely reason I'll be stuck in roughly the same place six months from now, and what one change would most move that? Answer specifically for me, not in generalities." },
  { id: 'p3', prompt: "Draft a 100-word speaker bio for me for an AI conference. It should sound like me and be true to what I'm actually building and why." },
  { id: 'p4', prompt: "I want to organize my week around 'velocity toward telos' instead of a flat task list. Give me a concrete weekly structure that fits how I actually operate and what I value." },
  { id: 'p5', prompt: "What's the one project or commitment I should drop this quarter to protect what matters most — and why that one?" },
]

const results = await parallel(TASKS.map((t, i) => () => runTask(t, i)))
return results.filter(Boolean)
