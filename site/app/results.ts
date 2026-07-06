// Results from experiments/psyche-injection. Aggregate metrics only — no private content.
// Two runs: v1 (signal-finding) and v2 (mechanism isolation — blind judges + objective scoring).
// The v1 -> v2 arc IS the finding. See experiments/psyche-injection/FINDINGS.md.

export const armColor: Record<string, string> = {
  naked: "#647089",
  context: "#38bdf8",
  psyche: "#7c5cff",
  best: "#ffd23f",
};

export const armLabel: Record<string, string> = {
  naked: "prompt only",
  context: "what's relevant",
  psyche: "who you are",
  best: "both",
};

// v2 — the honest run. Judges BLIND to how each answer was made (no "personal fit"
// dimension to reward the voice). Then a v3 CONFIDENCE run re-judged the same fixed
// answers with more blind judges -> 7 judges/task, 49 judgments total. Numbers below
// are the merged v2+v3 result. More judges did not overturn v2 — they tightened it.
export const v2 = {
  tasks: 9,
  identityTasks: 7,
  controls: 2,
  judgesPerTask: 7,
  judgments: 49, // on identity-shaped tasks (v2's 2 + v3's 5 per task)
  // Blind Borda (0-3 per ranking, summed over 49 judgments)
  borda: [
    { arm: "best", score: 118 },
    { arm: "context", score: 83 },
    { arm: "psyche", score: 65 },
    { arm: "naked", score: 28 },
  ],
  // Head-to-head win rates, blind
  pairwise: [
    { a: "best", b: "naked", rate: 88 },
    { a: "best", b: "psyche", rate: 82 },
    { a: "best", b: "context", rate: 71 },
    { a: "context", b: "psyche", rate: 59 },
    { a: "psyche", b: "naked", rate: 73 },
  ],
  // How often the ordering holds per task (out of 7 identity-shaped tasks)
  consistency: { bestOverContext: 6, bestOverPsyche: 6, contextOverPsyche: 6, ofTasks: 7 },
  rubric: {
    dims: ["specificity", "actionability", "correctness", "insight"],
    rows: [
      { arm: "naked", vals: [6.8, 7.9, 8.4, 6.7] },
      { arm: "context", vals: [8.6, 8.3, 8.5, 8.1] },
      { arm: "psyche", vals: [7.9, 7.3, 8.4, 8.9] },
      { arm: "best", vals: [8.7, 8.3, 8.7, 9.1] },
    ],
  },
  // Objective rubric-point pass rate on neutral technical controls (CAP theorem, LCS),
  // 4 scorers each. All arms tie at ceiling -> identity is NOT a global "try harder" effect.
  controlsPassRate: 100,
};

// v7 — the EXPANSION run. The one thing a re-judge can't buy is more tasks, so we
// added 7 fresh pre-registered tasks (t10-t16), generated + blind-judged identically
// (strict per-arm isolation). Combined = 12 identity tasks / 73 judgments. It tempers
// the pilot honestly: the ORDERING holds and both still beats identity-alone + naked,
// but the marginal edge of identity OVER retrieval did not replicate.
export const v7 = {
  identityTasks: 12,
  judgments: 73,
  borda: [
    { arm: "best", score: 156 },
    { arm: "context", score: 134 },
    { arm: "psyche", score: 91 },
    { arm: "naked", score: 57 },
  ],
  pairwise: [
    { a: "best", b: "naked", rate: 79 },
    { a: "best", b: "psyche", rate: 75 },
    { a: "best", b: "context", rate: 59 }, // down from the 7-task pilot's 71%
  ],
  // best beats context in 7 of 11 decidable tasks — sign test p=0.55, NOT significant
  bestOverContext: { tasks: 7, ofTasks: 11, pooledPct: 59, pilotPct: 71 },
};

// v1 — the first, non-blind run. Judges saw the answers and scored a "personal fit"
// dimension. Kept for the arc: it's what we then set out to break.
export const v1 = {
  tasks: 6,
  judgesPerTask: 3,
  borda: [
    { arm: "psyche", score: 41 },
    { arm: "best", score: 29 },
    { arm: "context", score: 15 },
    { arm: "naked", score: 5 },
  ],
};
