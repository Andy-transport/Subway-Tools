# Chengdu （成都） Metro — research notes (2026-11-19)

Full data: `research.json` in this directory. Research only; no app files touched.

## Headline

- **17 operating lines**: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 17, 18, 19, 27, 30 + S3 (Ziyang intercity).
- **449 line-stations, 364 unique stations** (79 interchanges: 6 three-line, 73 two-line).
  Verified by summing the station lists in `research.json` — every line's list
  length matches its claimed count and the total matches the published 449.
- **663.93 km** unique route-km (zh-Wikipedia line-table total). En-Wikipedia sums
  line lengths to 721.3 km because the 18/19 shared section is counted twice;
  do not use 721.3 km as the headline figure.
- **Fare**: distance-based, ¥2 for 0–4 km up to ¥13 for 110–130 km (12 bands).
  Worked checks: 犀浦→龙泉驿 (42.32 km) = ¥9; 福田→资阳北站 (38.7 km) = ¥8.
- **Theme**: Line 1 dark blue `#0F0F96`, darker accent `#0A0A6E` (derived).
- **Logo**: public-domain SVG on Wikimedia Commons,
  `Chengdu Rail Transit icon.svg` — NOT downloaded (Wikimedia returned HTTP 429
  to this VM); builder should download from
  https://upload.wikimedia.org/wikipedia/commons/b/bc/Chengdu_Rail_Transit_icon.svg
- **Transit app**: 成都地铁-官方APP, App Store id 1303414976. URL scheme UNVERIFIED.

## Must NOT be included (未开通)

- 6 built-but-unopened stations: 白仁店 (27), 玉虹路 / 分水 (30),
  天府机场3号4号航站楼 (18), 合江 (19), 芦葭 (S3).
- 10号线三期后通段： 文翁石室 / 人民公园 / 骡马市 (Line 10 platforms only;
  文翁石室 IS open on Line 13).
- 18号线三期 (north: 火车北站 / 骡马市 / 省体育馆 / 倪家桥; south: 官堰).
- S5线 (13 stations, to Meishan) and S11线 (16 stations, to Deyang) — under
  construction, expected end 2027.
- 5th-phase approved lines (5三期, 9二期, 10四期, 12, 16, 18四期, 20, 22, 23,
  27二期) and the Rong 2 tram.

## Traps found while researching

- **Line 2 east section was suspended 2025-12-20 → 2026-09-27** and resumed
  2026-09-28; new station 龙泉驿火车站 opened 2026-10-30. Older guides still
  show the suspension or the old 32-station count.
- **Three similar station names**: 龙泉驿火车站 (L2) vs 龙泉驿站 (L2 terminus)
  vs 龙泉驿火车站南站 (L30). Also 锦城广场 (L1) vs 锦城广场东 (L18) are
  separate stations (out-of-station transfer for now).
- **天府站 (18/19) is transfer-only** — no entry/exit.
- **Line 19 through-runs** to 天府机场北 on Line 18 tracks; its timetables are
  published for 金星 ↔ 天府机场北 even though its terminus is 天府站.
- **Line 10 has 19 stations, not 20**: 文翁石室 (Line 10) is not open despite
  appearing in one Wikipedia table with a 2025-12-16 date — that date is its
  Line 13 opening.
- **Timetables are secondary sources**: the official site (chengdurail.com)
  could not be fetched from this environment; Bendibao/gzhphb reproduce the
  official timetable. Verify against the official site before shipping.
  Per-station times were NOT collected (terminus first/last only).
- **Line 6 last train**: gzhphb says 22:30 both ends; dushiquan implies 22:39
  from 松林 — verify.
- **Fare estimation needs real OD distances** between stations (not collected);
  the band table alone cannot give exact fares.
- **Map/coordinates not sourced**: builder needs a Chengdu map SVG (railmapgen
  RMP gallery) + station coordinates; do not guess coordinates.

## Timetable — ESTIMATED (web/timetable/cd.json, 2026-11-19)

**The whole file is ESTIMATED, derived — not official per-station tables**,
exactly like Changchun's L1/L3/L4/L6/L7/L8. Per-station times were NOT
collected; only terminus first/last times exist in `research.json`
(secondary sources: Bendibao / gzhphb / dushiquan reproducing the official
Chengdu Metro timetable — the official site chengdurail.com could not be
fetched). **Verify every line against the official Chengdu Metro timetable
before shipping.** The app should flag Chengdu times as estimated (same
`tt.note` treatment as Changchun's estimated lines).

**Method**: per-station first/last = terminus departure time ± (intervals
from that terminus × **2.0 min**), same calibration as Changchun's estimated
lines (real L2/L5 tables there: 2.0–2.1 min/interval). Terminus entries use
the cc.json convention: the direction toward the station itself is
`{"dir": <self>, "first": null, "last": null}`. Coverage: **364 unique
stations, 449 line-stations, 17 lines** (keys 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
13, 17, 18, 19, 27, 30, S3) — verified against `research.json` (station sets,
per-station line sets, exclusion lists, time format, null convention, 24
hand-computed spot values; 0 failures).

**Line 1 branch** (main 33 + branch 广都/五根松， total 35): the shared
section 韦家碾–四河 gets **three** direction entries — 韦家碾 / 科学城 /
五根松 — because both branches serve it. Northbound （韦家碾） is a single
merged entry: first = earlier of the two branch services, last = later
(e.g. 四河 06:19/23:12; 天府广场 06:49/23:42). Main-south stations
(华阳–科学城） have only 韦家碾/科学城； branch stations only 韦家碾/五根松.
If the UI only renders two directions per line, the coordinator must decide
which southbound destination to show on the shared section — the data keeps
both; do not silently drop one.

**Line 7 loop**: station list order is the **外环** direction (proved by the
two published data points: 火车北站外环 06:15 → 北站西二路 06:17, +2 min;
北站西二路内环 06:16 → 火车北站 06:18, +2 min). Inner loop = reverse order,
interpolated from 火车北站内环 06:18/23:59, outer from 06:15/23:19. Dir
names are the source's own words: **内环 / 外环**. One exception:
**北站西二路内环 uses the published 06:16/23:57** (first/last inner trains
start/end there, by the depot) instead of the ring interpolation, which
would wrongly give 07:18/00:59. No null entries on a loop line.

**Line 18/19 shared section** （天府站–天府机场北）: each line computed on
its own times, never mixed — Line 18 from its 06:00/23:30 both ways; Line 19
from its through-service times 金星→天府机场北 06:00/23:00 and
天府机场北→金星 06:05/23:25. Line 19's eastbound dir is **天府机场北**,
not 天府站 (its nominal terminus — trains run through to the airport), and
its 金星-bound times count **4 shared-section intervals**
(天府机场北→天府站） plus the Line 19 intervals (e.g. 天府站金星方向
06:13/23:33, 天府机场北方向 06:34/23:34). Note 天府站's Line 18 and Line 19
times differ — that is correct, they are different services.

**Line 6 last-train discrepancy**: gzhphb says 22:30 both ends; dushiquan
implies 22:39 from 松林. **Used 22:30** (the terminus value, per the
researcher's instruction). Note the interpolated 松林 values are
toward 兰家沟 07:52/00:12 and toward 望丛祠 22:38 — dushiquan's 22:39 is
within 1 min of the 望丛祠-side value, so its "22:39 / 00:21" pair may
actually be the two directions mislabelled rather than a real conflict;
either way, verify Line 6 against the official timetable before shipping.

**Post-midnight last trains (80 entries)**: last trains departing a far
terminus at 22:30–23:00 arrive at far stations after 00:00. These are
written as **00:xx** (valid HH:MM) — so for those 80 entries first > last
numerically (e.g. 松林 6号线兰家沟方向 07:52/00:12, 九里堤 7号线内环
07:16/00:57). That is genuine, not an error; do not "fix" it by capping at
23:59. Affected: Line 7 (all inner-loop stations except 火车北站， plus
outer-loop stations from 成都东客站 on), Line 6 (both ends), Line 19
金星方向 (黄石/市五医院/凤溪河）, Lines 2/3/5/8 (far-end stations).

**Known weak spots** (verify first): the flat 2.0 min/interval rate
understates travel on the long-interval express lines — S3's published
end-to-end time is ~26 min vs 10 min interpolated (5 intervals), and Lines
18/19 have multi-km inter-station gaps at 140–160 km/h. Lines 10 and 17
have small/large (short-turn) routings (10: 武侯祠–花桥 short-turns;
17: 九江北–机车厂 short-turns) that are NOT modelled — only the full
terminus-to-terminus service is in the file.

## Builder notes — remap + stations/routes (2026-11-19)

**Files**: `stations.json` (364 stations) + `routes.json` (17 lines, 449
line-stations, 433 edges), both in the exact Changchun format
(`{"n","py","ini","x","y"}` sorted by py; `{"lines": {...}, "edges": [[a,b,line]]}`
with edges as consecutive pairs in line order). Verification script
(`/tmp/cd_verify.py`, build script `/tmp/cd_build.py`): ALL PASS.

**Match rate: 364/364.** Every operating station found on the map. No
operating station is missing; no coordinate was guessed. All coords are the
exact `translate(x, y)` of the station `<g>` in `map.svg` (root id `svg8`,
viewBox `-872.5 -747.5 1903 1555`; all x,y inside it).

**Name-variant match (1)**: research.json writes Line 30's station with
traditional 樹 (`棬子樹`); the map writes simplified 树 (`棬子树`). Same
station — confirmed by position on the Line 30 track between 金石路 and
锦逸 (pink edges 金石路–棬子树–锦逸）. `stations.json`/`routes.json` use the
research spelling `棬子樹` with the map's coords (95, 285).

**Same-name metro/tram disambiguation (3)**: 天河路 / 成都西站 / 望丛祠
each have TWO nodes — one metro, one Rong 2 tram (tram stroke `#7f9f3a`).
Kept the node touched by metro-coloured track edges:
天河路 (-485,-350, Line 2), 成都西站 (-455,-95, Line 4), 望丛祠 (-660,-590,
Line 6). 新业路 has two nodes, both tram-only — excluded entirely.

**Excluded, drawn in the SVG**: 3 not-yet-open stations — 分水 (460,155),
玉虹路 (460,190), 白仁店 (115,-430, next to a `暂未开通` label at
(115,-405); the other `暂未开通` label at (485,210) sits by 分水/玉虹路）.
The other 3 not-yet-open stations (合江， 天府机场3号4号航站楼， 芦葭） are
not drawn at all. 32 tram-only station names + the 3 shared names above =
Rong 2 tram, all excluded. Two unnamed, unconnected `stn_` nodes at
(785,-130) and (895,-135) carry no label and no track edge — stray RMP
nodes, not stations, excluded.

**Line 1 branch (Beijing T1 precedent, `finalize_routes.py`)**: the
stations list is a single ordered list with the branch stations inserted
right after the junction — `[..., 四河, 广都, 五根松, 华阳, ..., 科学城]`
(35 stations). Edges use the main chain (四河–华阳, 32 edges) PLUS the
spur edges 四河–广都 and 广都–五根松 (34 Line 1 edges total). There is
deliberately NO 五根松–华阳 or 科学城–广都 edge. The branch track is drawn
in the SVG: 四河 (-85,460) → (-85,485) → 广都 (-40,485).

**Line 7 loop**: stations listed in ring order from 火车北站 (the
researcher's `stations_loop_start_north_railway`, 外环 direction per the
timetable notes); edges include the closing edge 驷马桥–火车北站 (31 edges).
No `"loop": true` flag was added — Changchun format has none. Wiring step:
Beijing's format carries `"loop": true` and `template.html` reads it
(`ln.loop ? t('tt.loop') ...`, line 1103) for the timetable direction label,
so add `"loop": true` to Line 7 when wiring Chengdu in (or the timetable
will show 火车北站 — 驷马桥 instead of 环线）.

**Map-artwork notes (map.svg NOT edited; routing does not use SVG geometry)**:
- Line 30 玉石–惠王陵 has NO drawn segment in the artwork — the pink track
  ends at 玉石 (450,130) and resumes at (365,165) by 惠王陵. Both dots exist
  and are correctly placed; the edge is in `routes.json`. Cosmetic gap only.
- At interchanges the RMP track can sit up to 20 units from the dot, which
  sits on the crossing line's track: L8 珠江路 (dot on L30), L13 新南门 (dot
  on L3), L17 人民公园 (dot on L2), L30 双流机场2航站楼东 (dot on L19).
  Verification used a corridor check (420/433 edges directly confirmed by
  track geometry); the other 13 were each inspected by hand — 9 bowed tracks,
  3 dot-offset cases above, 1 artwork gap — none is a data error.
- Pinyin via pypinyin (style NORMAL); `·` stripped (中医大·省医院 →
  zhongyidashengyiyuan / zydsyy); digits kept as in Beijing
  (双流机场1航站楼 → shuangliujichang1hangzhanlou / sljc1hzl).
