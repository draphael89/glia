export const meta = {
  name: 'psyche-injection-ab',
  description: 'Blind A/B of two context-injection variants: generate an answer under each, then blind-judge which is better. Reusable for any injection change (dedup, format, budget, retrieval).',
  phases: [
    { title: 'Generate', detail: 'one answer per variant per task' },
    { title: 'JudgeBlind', detail: 'blind pairwise: which answer is better' },
  ],
}

const PERMS2 = [[0, 1], [1, 0]]  // A/B slot shuffle to kill position bias
const JUDGE_SCHEMA = {
  type: 'object',
  properties: {
    winner: { type: 'string', enum: ['A', 'B', 'tie'] },
    scores: { type: 'object', properties: {
      A: { type: 'object', properties: { specificity: { type: 'number' }, actionability: { type: 'number' }, insight: { type: 'number' } }, required: ['specificity', 'actionability', 'insight'] },
      B: { type: 'object', properties: { specificity: { type: 'number' }, actionability: { type: 'number' }, insight: { type: 'number' } }, required: ['specificity', 'actionability', 'insight'] },
    }, required: ['A', 'B'] },
    rationale: { type: 'string' },
  },
  required: ['winner', 'scores', 'rationale'],
}

function genPrompt(task, injFile) {
  return `You are answering on behalf of a specific person. Below is context priming you about who they are and what's relevant — read it from this file first:

    ${injFile}

Now answer their request, using that priming to serve THEM specifically (not generically):

TASK: ${task.prompt}

Write the single best answer for them: concrete, honest, genuinely useful, ~250-450 words. Output ONLY the answer.`
}

function judgePrompt(task, answers, permIdx) {
  const perm = PERMS2[permIdx]
  return `Two answers to the same task, produced for the same person. You do NOT know how either was made. Judge PURELY on quality for that person: specificity, actionability, genuine insight/usefulness. Do not reward length.

TASK: ${task.prompt}

--- ANSWER A ---
${answers[perm[0]]}

--- ANSWER B ---
${answers[perm[1]]}

Which is better? Score each (1-10), pick a winner (A/B/tie), 2-sentence rationale.`
}

async function runTask(task, tIdx) {
  // variantOrder[0] is the canonical "variant 0" injection, [1] is "variant 1"
  const answers = await parallel([task.injA, task.injB].map((f, i) => () =>
    agent(genPrompt(task, f), { label: `gen:${task.taskId}:v${i}`, phase: 'Generate' })))

  const judged = await parallel([0, 1].map((j) => () => {
    const permIdx = (tIdx + j) % PERMS2.length
    return agent(judgePrompt(task, answers, permIdx),
      { label: `judge:${task.taskId}:j${j}`, phase: 'JudgeBlind', schema: JUDGE_SCHEMA })
      .then((r) => {
        if (!r) return null
        // de-shuffle: map the judge's A/B (slot) back to canonical variant 0/1
        const perm = PERMS2[permIdx]
        const slotToVariant = { A: perm[0], B: perm[1] }
        const winnerVariant = r.winner === 'tie' ? 'tie' : slotToVariant[r.winner]
        return { permIdx, winnerVariant, scores: r.scores, rationale: r.rationale }
      })
  }))
  return { taskId: task.taskId, prompt: task.prompt, judgments: judged.filter(Boolean) }
}

const TASKS = typeof args === 'string' ? JSON.parse(args) : args
log(`inject A/B: ${TASKS.length} tasks — variant0 vs variant1, blind`)
const results = await parallel(TASKS.map((t, i) => () => runTask(t, i)))
return results.filter(Boolean)
