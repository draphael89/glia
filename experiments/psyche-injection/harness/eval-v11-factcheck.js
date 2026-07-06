export const meta = {
  name: 'psyche-injection-v11-factcheck',
  description: 'Fact-check the v9 identity answers (best/psyche arms) against the psyche: are their specific claims about the user SUPPORTED, CONTRADICTED (fabricated), or UNVERIFIABLE? Tests whether v9/v10 is a blind-judge FLOOR (real specifics penalized) or a real hallucination risk.',
  phases: [{ title: 'FactCheck', detail: '10 answers vs the psyche' }],
}

const PSYCHE = '/Users/david/.glia/psyche.md'
const MATDIR = '/Users/david/glia/experiments/psyche-injection/materials'

const SCHEMA = {
  type: 'object',
  properties: {
    claims: {
      type: 'array',
      description: 'Every SPECIFIC factual claim the answer makes ABOUT DAVID (his projects, people, values, situation) — not generic advice.',
      items: {
        type: 'object',
        properties: {
          claim: { type: 'string' },
          verdict: { type: 'string', enum: ['supported', 'contradicted', 'unverifiable'] },
          note: { type: 'string', description: 'brief evidence from the psyche, or why unverifiable' },
        },
        required: ['claim', 'verdict'],
      },
    },
  },
  required: ['claims'],
}

function prompt(a) {
  return `You are fact-checking an AI answer written FOR a specific person (David) against the GROUND TRUTH of who he is.

FIRST read ${PSYCHE} — this is the authoritative record of David's identity, projects, people, values, and situation. Read ONLY that file.

Then read this answer, which was written to serve David on the task below. Extract EVERY specific factual claim it makes ABOUT DAVID (his actual projects like Glia/Reflections, named people, his values/worldview, his concrete situation) — ignore generic advice that isn't a claim about him. For each claim, judge it against the psyche:
- "supported": the psyche corroborates it.
- "contradicted": the psyche says otherwise — a FABRICATION.
- "unverifiable": a specific-sounding claim the psyche neither confirms nor denies.

TASK (for context): ${a.prompt}

Then read the answer to check at ${MATDIR}/${a.taskId}-${a.arm}-ans.md (read ONLY the psyche file and that answer file — nothing else).

Be strict and literal. Return the structured list of claims with verdicts.`
}

const ITEMS = typeof args === 'string' ? JSON.parse(args) : args
const results = await parallel(ITEMS.map((a) => () =>
  agent(prompt(a), { label: `factcheck:${a.taskId}:${a.arm}`, phase: 'FactCheck', schema: SCHEMA })
    .then((r) => ({ taskId: a.taskId, arm: a.arm, claims: (r && r.claims) || [] }))
))
return results.filter(Boolean)
