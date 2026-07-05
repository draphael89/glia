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
