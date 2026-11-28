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
                            "sources": {"spatial": <url>, "plan": <url>},
                            "urls": {"spatial": <cdn url>, "plan": <cdn url>}} }

26E113: diagrams are no longer inlined into the offline page. Each
entry's "urls" point at the image's <file>.b64 twin in this repo,
served by the jsDelivr CDN pinned to the commit below (the branch
name test/structure contains a slash, which jsDelivr cannot parse
as a ref — a commit SHA always resolves). The .b64 files have not
changed since that commit; when images are next added or replaced,
push them first and then move this pin to the new head.
"""
import json
import urllib.parse
from pathlib import Path

BASE = Path(__file__).resolve().parent
SDIR = BASE / "structure"

# Commit on test/structure whose tree holds the current .b64 image
# files (the 26E112 head: 26E111 images + Pingguoyuan removal).
CDN_SHA = "538954cbd82732426b06e0921d64cb265b570f0a"
CDN_BASE = "https://cdn.jsdelivr.net/gh/Andy-transport/Subway-Tools@" + CDN_SHA + "/web/structure/"

index = {}

def cdn_url(file):
    return CDN_BASE + urllib.parse.quote(file + ".b64")

def put(city, station, kind, file, source):
    if not file:
        return
    if not (SDIR / file).exists():
        print(f"SKIP missing file: {file}")
        return
    if not (SDIR / (file + ".b64")).exists():
        print(f"SKIP missing .b64 twin: {file}.b64")
        return
    key = f"{city}:{station}"
    entry = index.setdefault(key, {"spatial": None, "plan": None, "sources": {}, "urls": {}})
    if entry.get(kind):
        print(f"KEEP first {kind} for {key}: {entry[kind]} (ignored {file})")
        return
    entry[kind] = file
    entry["sources"][kind] = source
    entry["urls"][kind] = cdn_url(file)

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

# 26E124: per-line diagram sets. sz:福田口岸 is an out-of-gate
# interchange (Lines 4 / 10) whose two harvested diagrams belong to
# DIFFERENT lines — the spatial diagram is Line 4's, the plan is
# Line 10's (the census collected one spatial + one plan per station
# regardless of line). Restructure the flat entry into "sets": one
# set per line, each carrying only the diagrams that belong to it.
# The flat spatial/plan fields stay for backward compatibility
# (list badges); the detail panel reads "sets" when present.
# The missing Line 4 plan and Line 10 spatial were NOT found on the
# szbus (深圳交通百科) wiki file list for this station (checked
# 2026-11-24) and szmc.net is unreachable from the build machine —
# they stay null, never substituted with another station's diagram.
_ft = index.get("sz:福田口岸")
if _ft:
    index["sz:福田口岸"] = dict(_ft, sets=[
        {"line": "4",
         "spatial": _ft.get("spatial"), "plan": None,
         "sources": {"spatial": (_ft.get("sources") or {}).get("spatial")},
         "urls": {"spatial": (_ft.get("urls") or {}).get("spatial")}},
        {"line": "10",
         "spatial": None, "plan": _ft.get("plan"),
         "sources": {"plan": (_ft.get("sources") or {}).get("plan")},
         "urls": {"plan": (_ft.get("urls") or {}).get("plan")}},
    ])

out = SDIR / "index.json"
out.write_text(json.dumps(index, ensure_ascii=False, indent=1), encoding="utf-8")
n_spatial = sum(1 for e in index.values() if e.get("spatial"))
n_plan = sum(1 for e in index.values() if e.get("plan"))
print(f"index.json: {len(index)} stations, spatial={n_spatial}, plan={n_plan}")
