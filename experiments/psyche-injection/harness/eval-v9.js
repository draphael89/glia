export const meta = {
  name: 'psyche-injection-eval-v9',
  description: 'PRODUCTION-PIPELINE run: generate answers from the ACTUAL shipped prime_context output (captured per task per mode) instead of a reconstruction, then blind-judge. Closes the experiment<->product gap.',
  phases: [
    { title: 'Generate', detail: '5 tasks x 4 arms (real injections)' },
    { title: 'JudgeBlind', detail: '5 judges/task, blind' },
  ],
}

const MATDIR = '/Users/david/glia/experiments/psyche-injection/materials'
const CONDITIONS = ['naked', 'context', 'psyche', 'best']  // best == the "both" injection
const MODE_FILE = { context: 'context', psyche: 'psyche', best: 'both' }
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

// The ONLY difference from v2/v7: the injected arms read the pre-assembled, REAL
// prime_context output (one file, already containing header+psyche+dedup'd
// retrieval), instead of reconstructing context from raw pages. Strict isolation.
function genPrompt(task, cond) {
  const reads = cond === 'naked'
    ? 'Answer from the task and your own general knowledge ALONE. Do NOT read any files, list any directory, or search — there is no primed context for you.'
    : `Read ONLY this one file: ${MATDIR}/${task.id}-${MODE_FILE[cond]}.md — it is the context glia-context primed into your session (who David is and/or what's relevant). Use it to serve David specifically. CRITICAL: read EXACTLY that one file and NOTHING else — do NOT list directories, grep, or open any other file.`
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
  return { taskId: task.id, kind: 'production', prompt: task.prompt, checkable: false,
           responses: resObj, blindJudgments: blind.filter(Boolean) }
}

const TASKS = typeof args === 'string' ? JSON.parse(args) : args
const results = await parallel(TASKS.map((t, i) => () => runTask(t, i)))
return results.filter(Boolean)
