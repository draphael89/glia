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
// dimension to reward the voice). 7 identity-shaped tasks + 2 objectively-graded controls.
export const v2 = {
  tasks: 9,
  identityTasks: 7,
  controls: 2,
  judgesPerTask: 2,
  judgments: 14, // on identity-shaped tasks
  // Blind Borda (0-3 per ranking, summed over 14 judgments)
  borda: [
    { arm: "best", score: 34 },
    { arm: "context", score: 25 },
    { arm: "psyche", score: 15 },
    { arm: "naked", score: 10 },
  ],
  // Head-to-head win rates, blind
  pairwise: [
    { a: "best", b: "naked", rate: 93 },
    { a: "best", b: "psyche", rate: 79 },
    { a: "best", b: "context", rate: 71 },
    { a: "context", b: "psyche", rate: 71 },
    { a: "psyche", b: "naked", rate: 57 },
  ],
  rubric: {
    dims: ["specificity", "actionability", "correctness", "insight"],
    rows: [
      { arm: "naked", vals: [7.0, 8.1, 8.2, 6.8] },
      { arm: "context", vals: [8.6, 8.4, 8.5, 8.1] },
      { arm: "psyche", vals: [7.4, 7.2, 8.2, 8.8] },
      { arm: "best", vals: [8.6, 8.3, 8.6, 9.0] },
    ],
  },
  // Objective rubric-point pass rate on neutral technical controls (CAP theorem, LCS).
  // All arms tie at ceiling -> identity is NOT a global "try harder" effect.
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
