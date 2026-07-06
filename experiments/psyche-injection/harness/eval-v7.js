export const meta = {
  name: 'psyche-injection-eval-v7',
  description: 'Expansion run: 7 FRESH tasks (t10-t16, pre-registered predictions) generated + blind-judged identically to v2, to attack the n=7 limitation the significance analysis flagged.',
  phases: [
    { title: 'Generate', detail: '7 fresh tasks x 4 arms' },
    { title: 'JudgeBlind', detail: '5 judges/task, NOT shown the psyche' },
    { title: 'ScoreObjective', detail: 'rubric correctness on the new control' },
  ],
}

const MATDIR = '/Users/david/glia/experiments/psyche-injection/materials'
const CONDITIONS = ['naked', 'context', 'psyche', 'best']
const PERMS = [[0,1,2,3],[3,2,1,0],[1,3,0,2],[2,0,3,1],[0,2,1,3],[3,1,2,0]]
const LETTERS = ['A','B','C','D']
const NJUDGES = 5   // more judges/task than v2 — these fresh tasks carry the power

const BLIND_SCORE = { type:'object', properties:{
  specificity:{type:'number'}, actionability:{type:'number'},
  correctness:{type:'number'}, insight:{type:'number'} },
  required:['specificity','actionability','correctness','insight'] }
const BLIND_JUDGE_SCHEMA = { type:'object', properties:{
  ranking:{ type:'array', items:{ type:'string', enum:['A','B','C','D'] }, minItems:4, maxItems:4 },
  scores:{ type:'object', properties:{ A:BLIND_SCORE, B:BLIND_SCORE, C:BLIND_SCORE, D:BLIND_SCORE }, required:['A','B','C','D'] },
  rationale:{ type:'string' } },
  required:['ranking','scores','rationale'] }

const OBJ_SCHEMA = { type:'object', properties:{
  perAnswer:{ type:'object', properties:{
    A:{type:'array',items:{type:'boolean'}}, B:{type:'array',items:{type:'boolean'}},
    C:{type:'array',items:{type:'boolean'}}, D:{type:'array',items:{type:'boolean'}} },
    required:['A','B','C','D'] },
  rationale:{ type:'string' } },
  required:['perAnswer'] }

// Same materials as v2, but with EXPLICIT read-isolation. v2's prompt named the
// file to read but didn't forbid exploring others; observed sporadic cross-arm
// leakage (a psyche arm grepping the context files) would collapse arm separation.
// Each arm now reads EXACTLY its assigned file(s) and nothing else — enforcing
// what the arm definitions always intended.
const ISOLATE = 'CRITICAL ISOLATION RULE: read EXACTLY the file(s) named above and NOTHING else. Do NOT list directories, do NOT grep/search the materials folder, do NOT open any other file. Your answer must rest only on the named file(s) plus your own general knowledge.'
function genPrompt(task, cond) {
  const reads = {
    naked: 'Answer from the task and your own general knowledge ALONE. Do NOT read any files, list any directory, or search — there are no materials for you.',
    context: `Read ONLY this one file: ${MATDIR}/${task.id}-context.md — relevant background from David's knowledge base. Ground the answer in it. ${ISOLATE}`,
    psyche: `Read ONLY this one file: ${MATDIR}/psyche.md — who David is: values, worldview, essays. Let who he is shape the answer. ${ISOLATE}`,
    best: `Read ONLY these two files: ${MATDIR}/${task.id}-context.md (background) AND ${MATDIR}/psyche.md (who David is). Use both. ${ISOLATE}`,
  }[cond]
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

function objScorePrompt(task, responses, permIdx) {
  const perm = PERMS[permIdx]
  let block = ''
  for (let k = 0; k < 4; k++) block += `\n--- ANSWER ${LETTERS[k]} ---\n${responses[perm[k]]}\n`
  const rubric = task.rubric.map((r, i) => `${i}. ${r}`).join('\n')
  return `Objectively grade four answers against a fixed correctness rubric. For each answer, return a boolean array (one per rubric point, in order) — true iff the answer satisfies that point. Be strict and literal; ignore style.

TASK: ${task.prompt}

RUBRIC (${task.rubric.length} points):
${rubric}
${block}
Return perAnswer: {A/B/C/D: [bool per rubric point]} and a short rationale.`
}

async function runTask(task, tIdx) {
  const responses = await parallel(
    CONDITIONS.map((c) => () => agent(genPrompt(task, c),
      { label: `gen:${task.id}:${c}`, phase: 'Generate' })))
  if (responses.some((r) => !r)) return null   // a dead arm invalidates the paired task

  // 5 judges, each a DIFFERENT permutation (gcd(5,6)=1 → 5 distinct perms/task)
  const blind = await parallel(Array.from({length: NJUDGES}, (_, j) => () => {
    const permIdx = (tIdx * NJUDGES + j) % PERMS.length
    return agent(blindJudgePrompt(task, responses, permIdx),
      { label: `blind:${task.id}:j${j}`, phase: 'JudgeBlind', schema: BLIND_JUDGE_SCHEMA })
      .then((r) => r && r.ranking ? { permIdx, ranking: r.ranking, scores: r.scores, rationale: r.rationale } : null)
  }))

  let objective = null
  if (task.checkable) {
    const permIdx = (tIdx * NJUDGES) % PERMS.length
    const o = await agent(objScorePrompt(task, responses, permIdx),
      { label: `obj:${task.id}`, phase: 'ScoreObjective', schema: OBJ_SCHEMA })
    objective = { permIdx, perAnswer: o?.perAnswer, rationale: o?.rationale, nPoints: task.rubric.length }
  }

  const resObj = {}; CONDITIONS.forEach((c, ci) => { resObj[c] = responses[ci] })
  return { taskId: task.id, kind: task.kind, prompt: task.prompt, checkable: !!task.checkable,
           predict: task.predict || null,
           responses: resObj, blindJudgments: blind.filter(Boolean), objective }
}

const TASKS = typeof args === 'string' ? JSON.parse(args) : args
const results = await parallel(TASKS.map((t, i) => () => runTask(t, i)))
return results.filter(Boolean)
