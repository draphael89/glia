#!/usr/bin/env python3
"""Generate the bundled demo brain: a synthetic, fully fictional knowledge
graph that shows off clusters, types, growth replay, and dark matter —
without a byte of anyone's real data. Deterministic (seeded)."""
import json
import random
from datetime import date, timedelta

random.seed(414)

NODES, LINKS = [], []
_id = 0


def add(slug, type_, title, created, source="demo"):
    global _id
    _id += 1
    NODES.append({
        "id": _id, "slug": slug, "type": type_, "source": source,
        "title": title, "created": created.isoformat(),
        "updated": created.isoformat() + "T12:00:00Z",
    })
    return _id


def link(a, b, t="mentions"):
    LINKS.append({"source": a, "target": b, "type": t})


START = date(2026, 1, 6)

# ---- People hub -----------------------------------------------------------
people = [
    ("ada-lovelace", "Ada Lovelace"), ("alan-turing", "Alan Turing"),
    ("grace-hopper", "Grace Hopper"), ("claude-shannon", "Claude Shannon"),
    ("margaret-hamilton", "Margaret Hamilton"), ("john-von-neumann", "John von Neumann"),
]
people_ids = [add(f"people/{s}", "person", n, START + timedelta(days=i * 3))
              for i, (s, n) in enumerate(people)]

companies = [("acme-labs", "Acme Labs"), ("widget-co", "Widget Co"),
             ("orbital-systems", "Orbital Systems")]
company_ids = [add(f"companies/{s}", "company", n, START + timedelta(days=10 + i * 5))
               for i, (s, n) in enumerate(companies)]

concepts = [("hypertext", "Hypertext"), ("information-theory", "Information Theory"),
            ("compilers", "Compilers"), ("apollo-guidance", "Apollo Guidance"),
            ("analytical-engine", "Analytical Engine"), ("cybernetics", "Cybernetics")]
concept_ids = [add(f"concepts/{s}", "concept", n, START + timedelta(days=5 + i * 7))
               for i, (s, n) in enumerate(concepts)]

# wire people <-> concepts/companies
link(people_ids[0], concept_ids[4], "created")
link(people_ids[1], concept_ids[1], "influenced")
link(people_ids[2], concept_ids[2], "created")
link(people_ids[3], concept_ids[1], "created")
link(people_ids[3], concept_ids[5], "influenced")
link(people_ids[4], concept_ids[3], "led")
for i, p in enumerate(people_ids):
    link(p, company_ids[i % 3], "works_with")

# ---- Meeting notes accrete over six months --------------------------------
topics = ["sync", "review", "planning", "retro", "kickoff", "deep dive"]
for week in range(24):
    day = START + timedelta(days=7 * week + 2)
    n = random.randint(2, 5)
    for k in range(n):
        person = random.choice(people_ids)
        topic = random.choice(topics)
        who = NODES[person - 1]["title"].split()[0]
        nid = add(f"notes/{day.isoformat()}-{who.lower()}-{topic.replace(' ', '-')}-{k}",
                  "note", f"{who} — {topic} ({day.strftime('%b %d')})",
                  day + timedelta(days=random.randint(0, 4)))
        link(nid, person, "attended")
        if random.random() < 0.6:
            link(nid, random.choice(concept_ids), "mentions")
        if random.random() < 0.3:
            link(nid, random.choice(company_ids), "mentions")

# ---- Atom layer (some linked, some dark matter) ----------------------------
facts = ["prefers morning reviews", "shipped the prototype", "raised a concern",
         "proposed an experiment", "closed the loop", "flagged a risk"]
for i in range(220):
    day = START + timedelta(days=random.randint(3, 168))
    nid = add(f"atoms/{day.isoformat()}/atom-{i}", "atom",
              f"{random.choice(facts).capitalize()} #{i}", day)
    r = random.random()
    if r < 0.35:
        link(nid, random.choice(people_ids + concept_ids), "extracted_from")
    # else: orphan — the demo gets its dust halo too

# ---- A second, smaller source to show source tinting -----------------------
side_ids = []
for i, name in enumerate(["Field Notes", "Lab Journal", "Reading List"]):
    nid = add(f"journal/{name.lower().replace(' ', '-')}", "original", name,
              START + timedelta(days=40 + i * 20), source="sandbox")
    side_ids.append(nid)
    # anchor each journal to its keeper — keeps the constellation composed
    # (disconnected components drift to the frame edges otherwise)
    link(nid, people_ids[i * 2], "kept_by")
for i in range(30):
    day = START + timedelta(days=random.randint(45, 160))
    nid = add(f"journal/entries/{day.isoformat()}-{i}", "note",
              f"Entry — {day.strftime('%b %d')}", day, source="sandbox")
    link(nid, random.choice(side_ids), "part_of")

out = {
    "generated_at": "2026-06-30T12:00:00Z",
    "nodes": NODES,
    "links": LINKS,
}
with open("Glia/Resources/DemoBrain.json", "w") as f:
    json.dump(out, f, separators=(",", ":"))
print(f"demo brain: {len(NODES)} nodes, {len(LINKS)} links")
