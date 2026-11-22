#!/usr/bin/env python3
"""Build web/structure/index.json for the TEST-BUILD "structure" tab.

Sources of truth:
- census-*.json files in the same directory, produced by the source
  census: each entry names a station, the downloaded file and the
  source URL it was verified against. Only entries whose file exists
  on disk are compiled in. Stations absent from the index show the
  "being prepared" placeholder in the app — nothing is fabricated.
  (26E112: the user's own Pingguoyuan photos that used to be
  hardcoded here were removed at the user's request; Pingguoyuan
  now shows the placeholder like any station without diagrams.)

Index shape (consumed by template.html via build_offline.py):
  { "<cityKey>:<station>": {"spatial": <file|null>, "plan": <file|null>,
                            "sources": {"spatial": <url>, "plan": <url>}} }
"""
import json
from pathlib import Path

BASE = Path(__file__).resolve().parent
SDIR = BASE / "structure"

index = {}

def put(city, station, kind, file, source):
    if not file:
        return
    if not (SDIR / file).exists():
        print(f"SKIP missing file: {file}")
        return
    key = f"{city}:{station}"
    entry = index.setdefault(key, {"spatial": None, "plan": None, "sources": {}})
    if entry.get(kind):
        print(f"KEEP first {kind} for {key}: {entry[kind]} (ignored {file})")
        return
    entry[kind] = file
    entry["sources"][kind] = source

# Census downloads. (The hardcoded Pingguoyuan entries that used
# to sit here were removed in 26E112 — see the header note.)
for census_path in sorted(SDIR.glob("census-*.json")):
    data = json.loads(census_path.read_text(encoding="utf-8"))
    for city in data.get("cities", []):
        key = city.get("key")
        for kind in ("spatial", "plan"):
            for item in city.get(kind, []) or []:
                put(key, item.get("station"), kind, item.get("file"),
                    item.get("source_url") or item.get("source_page") or "")

out = SDIR / "index.json"
out.write_text(json.dumps(index, ensure_ascii=False, indent=1), encoding="utf-8")
n_spatial = sum(1 for e in index.values() if e.get("spatial"))
n_plan = sum(1 for e in index.values() if e.get("plan"))
print(f"index.json: {len(index)} stations, spatial={n_spatial}, plan={n_plan}")
