#!/usr/bin/env python3
"""Aggregate v11 — fact-check of the v9 identity answers against the psyche. Tests
whether the v9/v10 "retrieval beats injected identity" result is a blind-judge FLOOR
(the identity answers' specifics are REAL — supported by the psyche — but a blind
judge penalized them as unverifiable) or a real HALLUCINATION risk (the answers
fabricate specifics the psyche contradicts).

Reads results/raw/results-v11.json (list of {taskId, arm, claims:[{claim,verdict}]}).
Writes REPORT-v11.md. Aggregate only — the claims themselves stay private.
"""
import json, os
from collections import defaultdict

base = os.path.dirname(os.path.abspath(__file__))


def main():
    path = os.path.join(base, "results/raw/results-v11.json")
    if not os.path.exists(path):
        print("results-v11.json not present — run the v11 workflow first."); return
    data = json.load(open(path))
    tot = defaultdict(int); by_arm = {"best": defaultdict(int), "psyche": defaultdict(int)}
    n_answers = 0
    for r in data:
        n_answers += 1
        arm = r.get("arm", "?")
        for c in r.get("claims", []):
            v = c.get("verdict", "unverifiable")
            tot[v] += 1
            if arm in by_arm: by_arm[arm][v] += 1

    total_claims = sum(tot.values())
    out = ["# Psyche Injection — v11 (are the identity answers' specifics REAL or fabricated?)\n",
           "_Fact-checks every specific claim ABOUT DAVID in the v9 `best`+`psyche` answers against "
           "the psyche (informed Opus checker). Distinguishes a blind-judge FLOOR from hallucination._\n"]
    if not total_claims:
        out.append("No claims extracted."); open(os.path.join(base, "REPORT-v11.md"), "w").write("\n".join(out)); print("\n".join(out)); return

    def pct(v, d): return f"{100*v/d:.0f}%" if d else "-"
    sup, con, unv = tot["supported"], tot["contradicted"], tot["unverifiable"]
    out.append(f"## {total_claims} identity-claims across {n_answers} answers\n")
    out.append(f"- **supported (psyche corroborates): {sup} ({pct(sup,total_claims)})**")
    out.append(f"- **contradicted (fabrication): {con} ({pct(con,total_claims)})**")
    out.append(f"- unverifiable (specific but psyche silent): {unv} ({pct(unv,total_claims)})")
    out.append(f"\n- verifiable claims (supported+contradicted): {sup+con}; of those, "
               f"**{pct(sup, sup+con)} are SUPPORTED, {pct(con, sup+con)} fabricated**")
    for arm in ("best", "psyche"):
        a = by_arm[arm]; at = sum(a.values())
        if at: out.append(f"- {arm}: {a['supported']} sup / {a['contradicted']} contra / {a['unverifiable']} unver ({at} claims)")

    out.append("\n## Verdict\n")
    fab_rate = con / (sup + con) if (sup + con) else 0
    if fab_rate <= 0.1:
        out.append(f"- **It's a FLOOR, confirmed.** The identity answers' specifics are overwhelmingly "
                   f"REAL — only {pct(con, sup+con)} of verifiable claims are fabricated. So when the "
                   "blind judges in v9/v10 preferred retrieval and marked the injected arms down, they "
                   "were penalizing **accurate** identity content they simply couldn't verify (the v6 "
                   "fabrication penalty). The verification-blind measurement UNDERSTATES identity; the "
                   "user, who can verify, would value what the judge discounted.")
    elif fab_rate >= 0.25:
        out.append(f"- **Real HALLUCINATION risk.** {pct(con, sup+con)} of verifiable identity claims are "
                   "fabricated (psyche-contradicted). Injecting identity makes the model assert specific, "
                   "confident, WRONG things about the user — so v9/v10's blind-judge preference for "
                   "retrieval is partly EARNED, not just a floor. This is a product concern worth fixing.")
    else:
        out.append(f"- **Mixed.** {pct(sup, sup+con)} of verifiable claims supported, {pct(con, sup+con)} "
                   "fabricated — mostly a floor (real specifics penalized blind), but a non-trivial "
                   "fabrication tail that injection should guard against.")
    out.append("\n---\n_Informed Opus checker; psyche stays internal; claims private, rates only. aggregate-v11.py._")
    open(os.path.join(base, "REPORT-v11.md"), "w").write("\n".join(out) + "\n")
    print("\n".join(out))


if __name__ == "__main__":
    main()
