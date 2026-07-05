// Results from experiments/psyche-injection (pilot v1). Updated as runs land.
// Aggregate metrics only — no private content.

export const pilot = {
  tasks: 6,
  sensitive: 5,
  controls: 1,
  judgesPerTask: 3,
  // Borda (0-3 per ranking) on psyche-sensitive tasks
  borda: [
    { arm: "psyche", score: 41, label: "who you are" },
    { arm: "best", score: 29, label: "both" },
    { arm: "context", score: 15, label: "what's relevant" },
    { arm: "naked", score: 5, label: "prompt only" },
  ],
  pairwise: [
    { a: "psyche", b: "naked", rate: 100 },
    { a: "psyche", b: "context", rate: 93 },
    { a: "best", b: "context", rate: 73 },
    { a: "context", b: "naked", rate: 67 },
    { a: "best", b: "psyche", rate: 20 },
  ],
  rubric: {
    dims: ["specificity", "actionability", "personalFit", "insight"],
    rows: [
      { arm: "naked", vals: [5.8, 7.5, 4.9, 6.3] },
      { arm: "context", vals: [8.5, 8.4, 7.3, 7.2] },
      { arm: "psyche", vals: [8.7, 7.9, 9.5, 9.3] },
      { arm: "best", vals: [8.6, 7.9, 9.1, 8.6] },
    ],
  },
};

export const armColor: Record<string, string> = {
  naked: "#647089",
  context: "#38bdf8",
  psyche: "#7c5cff",
  best: "#ffd23f",
};
