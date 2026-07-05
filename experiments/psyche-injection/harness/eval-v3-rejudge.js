export const meta = {
  name: 'psyche-injection-eval-v3-rejudge',
  description: 'Confidence power-up: re-judge the FIXED v2 answers with more blind judges (5/task) + more objective scorers (3/control) to tighten the ranking intervals.',
  phases: [
    { title: 'JudgeBlind', detail: '5 blind judges/task on the saved answers' },
    { title: 'ScoreObjective', detail: '3 objective scorers/control' },
  ],
}

// Answers live in pre-written, ANONYMIZED files (arm identity stripped, shuffled
// to A/B/C/D per that judge's perm). Judges read their file — so this workflow
// carries only tiny metadata in args, and judges literally cannot see arm labels.
const N_OBJ = 3

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

function blindJudgePrompt(task, file) {
  return `Evaluate four answers to the same task. You do NOT know anything about who requested them or how each was produced. Read the four candidate answers here (labeled ANSWER A, B, C, D):

    ${file}

Judge PURELY on general quality: specificity, actionability, correctness/soundness, and genuine insight/usefulness. Do not reward verbosity or confident-sounding filler.

TASK: ${task.prompt}

Rank best-to-worst (A/B/C/D), give per-answer rubric scores (1-10), and a 2-sentence rationale.`
}

function objScorePrompt(task, file) {
  const rubric = task.rubric.map((r, i) => `${i}. ${r}`).join('\n')
  return `Objectively grade four answers against a fixed correctness rubric. Read the four answers here (labeled ANSWER A, B, C, D):

    ${file}

For each answer, return a boolean array (one per rubric point, in order) — true iff the answer satisfies that point. Be strict and literal; ignore style. If an answer contains runnable code, mentally execute it.

TASK: ${task.prompt}

RUBRIC (${task.rubric.length} points):
${rubric}

Return perAnswer: {A/B/C/D: [bool per rubric point]} and a short rationale.`
}

async function runTask(task) {
  const blind = await parallel(task.judges.map((jd, j) => () =>
    agent(blindJudgePrompt(task, jd.file),
      { label: `blind:${task.taskId}:j${j}`, phase: 'JudgeBlind', schema: BLIND_JUDGE_SCHEMA })
      .then((r) => r ? ({ permIdx: jd.permIdx, ranking: r.ranking, scores: r.scores, rationale: r.rationale }) : null)))

  let objectiveScorers = []
  if (task.checkable && task.rubric) {
    objectiveScorers = await parallel(task.judges.slice(0, N_OBJ).map((jd, j) => () =>
      agent(objScorePrompt(task, jd.file),
        { label: `obj:${task.taskId}:j${j}`, phase: 'ScoreObjective', schema: OBJ_SCHEMA })
        .then((o) => o ? ({ permIdx: jd.permIdx, perAnswer: o.perAnswer, rationale: o.rationale, nPoints: task.rubric.length }) : null)))
  }

  return { taskId: task.taskId, checkable: !!task.checkable,
           blindJudgments: blind.filter(Boolean),
           objectiveScorers: objectiveScorers.filter(Boolean) }
}

const TASKS = typeof args === 'string' ? JSON.parse(args) : args
log(`v3 re-judge: ${TASKS.length} tasks x ${TASKS[0].judges.length} blind judges on FIXED answers`)
const results = await parallel(TASKS.map((t) => () => runTask(t)))
return results.filter(Boolean)
