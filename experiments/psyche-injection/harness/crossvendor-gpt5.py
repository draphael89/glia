#!/usr/bin/env python3
"""v6 — cross-vendor judge with gpt-5 (OpenAI frontier, discriminating — unlike
gpt-4o which was 90% position-biased here). Blind-judges the FIXED Opus answers.
3 judges/task, run concurrently. Writes results/raw/results-v6-gpt5.json."""
import json, os, re, urllib.request, urllib.error, time
from concurrent.futures import ThreadPoolExecutor

CONDS = ["naked", "context", "psyche", "best"]
PERMS = [[0,1,2,3],[3,2,1,0],[1,3,0,2],[2,0,3,1],[0,2,1,3],[3,1,2,0]]
L = ["A","B","C","D"]; DIMS=["specificity","actionability","correctness","insight"]
KEY = re.search(r'^OPENAI_API_KEY=["\']?([^"\'\n]+)', open(os.path.expanduser("~/.hermes/.env")).read(), re.M).group(1).strip()
base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def call(prompt):
    body = json.dumps({"model": "gpt-5", "messages": [{"role": "user", "content": prompt}],
                       "response_format": {"type": "json_object"}, "reasoning_effort": "low",
                       # gpt-5's reasoning tokens count toward this; too low → empty output
                       # (finish_reason=length) → JSON parse fails. 16k leaves room for the answer.
                       "max_completion_tokens": 16000}).encode()
    for a in range(3):
        try:
            req = urllib.request.Request("https://api.openai.com/v1/chat/completions", data=body,
                headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
            r = json.load(urllib.request.urlopen(req, timeout=240))
            return json.loads(r["choices"][0]["message"]["content"])
        except urllib.error.HTTPError as e:
            if e.code == 429: time.sleep(8*(a+1)); continue
            print("  HTTP", e.code, e.read().decode()[:120]); return None
        except Exception as ex:
            time.sleep(4); continue
    return None

def prompt_for(task, arr, permIdx):
    perm = PERMS[permIdx]
    block = "".join(f"\n--- ANSWER {L[k]} ---\n{arr[perm[k]]}\n" for k in range(4))
    return (f"Evaluate four answers to the same task. Their A/B/C/D order is RANDOMIZED and meaningless — "
            f"judge strictly on content, not position. Rate specificity, actionability, correctness, and genuine "
            f"insight/usefulness.\n\nTASK: {task}\n{block}\n"
            f'Return ONLY JSON: {{"ranking":["A|B|C|D" best-to-worst, all four],'
            f'"scores":{{"A":{{"specificity":n,"actionability":n,"correctness":n,"insight":n}},"B":{{...}},"C":{{...}},"D":{{...}}}},'
            f'"rationale":"2 sentences"}}')

v2 = json.load(open(os.path.join(base, "results/raw/results-v2.json")))
tasks = [t for t in v2 if not t.get("checkable")]

def one(args):
    t, j = args
    tIdx = [x["taskId"] for x in tasks].index(t["taskId"])
    permIdx = (tIdx * 4 + j) % len(PERMS)
    arr = [t["responses"][c] for c in CONDS]
    r = call(prompt_for(t["prompt"], arr, permIdx))
    if r and r.get("ranking") and len(r["ranking"]) == 4:
        print(f"  {t['taskId']} j{j}: {r['ranking']}")
        return (t["taskId"], {"model": "gpt-5", "permIdx": permIdx, "ranking": r["ranking"],
                              "scores": r.get("scores", {}), "rationale": r.get("rationale", "")})
    print(f"  {t['taskId']} j{j}: FAILED")
    return (t["taskId"], None)

jobs = [(t, j) for t in tasks for j in range(4)]
dest = os.path.join(base, "results/raw/results-v6-gpt5.json")
# Accumulate across runs (each run adds judgments; dedup by permIdx per task).
by_task = {t["taskId"]: [] for t in tasks}
if os.path.exists(dest):
    for t in json.load(open(dest)):
        by_task.setdefault(t["taskId"], []).extend(t.get("blindJudgments", []))
with ThreadPoolExecutor(max_workers=5) as ex:
    for tid, jm in ex.map(one, jobs):
        if jm and not any(x["permIdx"] == jm["permIdx"] for x in by_task[tid]):
            by_task[tid].append(jm)

out = [{"taskId": t["taskId"], "checkable": False, "blindJudgments": by_task[t["taskId"]]} for t in tasks]
json.dump(out, open(dest, "w"), indent=2)
print(f"\nwrote {dest}: {sum(len(t['blindJudgments']) for t in out)} gpt-5 judgments")
