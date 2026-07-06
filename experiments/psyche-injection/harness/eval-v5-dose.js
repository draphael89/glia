export const meta = {
  name: 'psyche-injection-eval-v5-dose',
  description: 'Dose-response: does the identity lift saturate at a small psyche dose? Generate a psyche-arm answer at 4 truncation budgets (tiny/small/medium/full), then blind-rank them. Tests the MCP\'s "concentrated core suffices" claim.',
  phases: [
    { title: 'Generate', detail: '5 tasks x 4 doses' },
    { title: 'JudgeBlind', detail: '2 judges/task rank the 4 doses blind' },
  ],
}

// Doses in canonical order; index maps through PERMS for blind slotting.
const DOSES = ['tiny', 'small', 'medium', 'full']
const PERMS = [[0,1,2,3],[3,2,1,0],[1,3,0,2],[2,0,3,1],[0,2,1,3],[3,1,2,0]]
const LETTERS = ['A','B','C','D']

const BLIND_SCORE = { type:'object', properties:{
  specificity:{type:'number'}, actionability:{type:'number'},
  correctness:{type:'number'}, insight:{type:'number'} },
  required:['specificity','actionability','correctness','insight'] }
const JUDGE_SCHEMA = { type:'object', properties:{
  ranking:{ type:'array', items:{ type:'string', enum:['A','B','C','D'] }, minItems:4, maxItems:4 },
  scores:{ type:'object', properties:{ A:BLIND_SCORE, B:BLIND_SCORE, C:BLIND_SCORE, D:BLIND_SCORE }, required:['A','B','C','D'] },
  rationale:{ type:'string' } },
  required:['ranking','scores','rationale'] }

function genPrompt(task, doseFile) {
  return `You are answering on behalf of David. First read ${doseFile} — who David is (values, worldview, essays). Let who he is shape the answer.

TASK: ${task.prompt}

Write the ideal answer FOR HIM specifically: concrete, honest, genuinely useful, ~250-450 words. Output ONLY the answer text.`
}

function judgePrompt(task, answers, permIdx) {
  const perm = PERMS[permIdx]
  let block = ''
  for (let k = 0; k < 4; k++) block += `\n--- ANSWER ${LETTERS[k]} ---\n${answers[perm[k]]}\n`
  return `Evaluate four answers to the same task. You do NOT know how any was produced. Judge PURELY on general quality: specificity, actionability, correctness, and genuine insight/usefulness. Do not reward verbosity.

TASK: ${task.prompt}
${block}
Rank best-to-worst (A/B/C/D), give per-answer rubric scores (1-10), and a 2-sentence rationale.`
}

async function runTask(task, tIdx) {
  // generate one answer per dose (canonical order)
  const answers = await parallel(DOSES.map((d, di) => () =>
    agent(genPrompt(task, task.doseFiles[di]),
      { label: `gen:${task.id}:${d}`, phase: 'Generate' })))
  // 2 blind judges rank the 4 dose-answers, slots permuted
  const blind = await parallel([0, 1].map((j) => () => {
    const permIdx = (tIdx * 2 + j) % PERMS.length
    return agent(judgePrompt(task, answers, permIdx),
      { label: `judge:${task.id}:j${j}`, phase: 'JudgeBlind', schema: JUDGE_SCHEMA })
      .then((r) => r ? ({ permIdx, ranking: r.ranking, scores: r.scores, rationale: r.rationale }) : null)
  }))
  return { taskId: task.id, prompt: task.prompt, doses: DOSES, blindJudgments: blind.filter(Boolean) }
}

const TASKS = typeof args === 'string' ? JSON.parse(args) : args
log(`v5 dose-response: ${TASKS.length} tasks x ${DOSES.length} doses (${DOSES.join('/')})`)
const results = await parallel(TASKS.map((t, i) => () => runTask(t, i)))
return results.filter(Boolean)
