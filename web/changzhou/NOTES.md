# Changzhou Metro (常州地铁) — NOTES (web/changzhou/)

Changzhou support for Subway motion, 7th city (`cz`). Two operating lines,
**43 unique operating stations** (see the 43-vs-44 note below).

## Network (verified 2026-11-17, user map + Wikipedia line tables)

| Key | Line | Colour | Stations | Opened | Length | Termini |
|-----|------|--------|----------|--------|--------|---------|
| 1 | 1号线 | red `CD5C5C` | 29 | 2019-09-21 | 34.24 km | 森林公园 → 南夏墅 |
| 2 | 2号线 | blue `529FC9` | 15 | 2021-06-28 | 19.79 km | 青枫公园 → 五一路 |

Line entries total 44; 文化宫 appears in both lines, so 44 − 1 = **43 unique
stations**. 文化宫 is the only interchange (1 + 2).

1号线 (north → south): 森林公园、新龙、旅游学校、新桥、常州北站、北郊中学、
外国语学校、环球港、新区公园、河海、奥体中心、市民广场、翠竹、常州火车站、
博爱路、文化宫、同济桥、清凉寺、茶山、聚湖路、湖塘、新天地公园、长虹路、
延政大道、科教城北、科教城南、武进沿江城际、阳湖路、南夏墅.

2号线 (west → east): 青枫公园、海棠路、五星、勤业、怀德、南大街、文化宫、
红梅公园、五角场、三角场、紫云、青洋路、丁堰、潞城、五一路.

**Excluded — NOT operating (drawn on the map, NOT in any data file)**:
- **5号线** (green): UNDER CONSTRUCTION, started Oct 2023, expected 2028,
  25 stations 揽月湾—东青. Not in stations.json / routes.json / cz.json.
- **6号线** (yellow/orange): UNDER CONSTRUCTION, started Oct 2024,
  expected Dec 2029, 21 stations phase 1 武进沿江城际—建业路. Same exclusion.
- Per the parent rule (2026-11-17): unopened lines must not appear in the
  searchable/routable data, even though the map image shows them. The map
  is used as-is (JPEG-in-SVG); the drawn 5/6号线 remain visible on the image,
  which is a known cosmetic caveat, not a data error.

**43 vs published 44**: metroeasy.com says 44 stations — wrong, it
double-counts 文化宫. en.wikipedia.org + Railway Gazette confirm 43
(29 + 15 − 1). Do NOT silently claim 44.

**Future interchanges (NOT operating, NOT marked as interchanges)**:
新区公园 (6号线在建), 翠竹 (5号线在建), 武进沿江城际 (6号线在建),
怀德 (5号线在建), 紫云 (6号线在建). These are single-line stations in the
data until 5/6号线 open.

## Station names — map labels vs official names

- Map "丁塘" (top-right area) is actually **丁堰** (DINGYAN) — confirmed in
  the top-right crop and by the Wikipedia 2号线 station table.
- All other map labels match the official names exactly (verified against
  the zh Wikipedia 1号线 / 2号线 station tables).

## Station coordinates (map 1206×1419, user's image)

Station dots are small white circles (~6 px) on the coloured lines.
Method used (unlike Jinhua's chainage interpolation — these dots ARE
machine-detectable):
- Located the line geometry by pixel scans: Line 1 north vertical x≈362,
  horizontal y≈290, south vertical x≈530; Line 2 horizontal y≈681.
- Detected station dots via white-component + centreline-scan methods,
  then pinned the three interchange double-dots (怀德, 紫云, 武进沿江城际)
  by line-mask intersections, not by the white-dot scan.
- Validated with a numbered overlay (`/tmp/cz_overlay.png`): all 43 dots
  land on their line, in the correct order, next to their labels.
- One subtlety: 环球港 (530, 314.5) sits just BELOW the corner where the
  horizontal meets the south vertical — confirmed by a corner crop.

**px/km (for the fare model)**: Line 1 **38.12** (1305.2 px / 34.24 km),
Line 2 **42.22** (835.5 px / 19.79 km). See WIRING.md for how to use these
in `shScaleFor`.

No coordinates were fabricated; every dot was detected on the image and
validated on the overlay.

## Map

`map.svg` is a JPEG-in-SVG wrapper (the user's map JPEG embedded, bytes
identical), the same approach as Shanghai/Harbin/Dalian/Jinhua. No true
vector trace is feasible from this raster image — **zoom will blur** past
~2× (same caveat as the other raster cities; only Beijing is true vector).

## Fare (VERIFIED, zh Wikipedia 常州地铁 + 常州本地宝）

Distance-based, by ride distance (km):
- ≤ 5 km → ¥2
- 5–10 km → ¥3
- 10–15 km → ¥4
- 15–22 km → ¥5
- 22–29 km → ¥6
- > 29 km → ¥6 + ceil((km − 29) / 9)

Cross-check (published): 森林公园—南夏墅 full Line 1 (34.24 km) = **¥7**.
The app should reproduce this from the pixel distances (see WIRING.md).
Intermediate fares are computed from the schematic map scale and are
estimates (e.g. 文化宫—南夏墅 ≈ 16.3 km → ¥5); only the ¥7 end-to-end
check is published-verified.

Note: 龙城通卡 / 市民卡 get 9.5折 (5% off) — **no fare discount is applied
in the app** (same rule as build 66: no per-city card-vs-cash rule is
implemented; do not invent one).

## Timetable (MOSTLY REAL — one open question, see below)

`web/timetable/cz.json` is transcribed from two sources:
- **Line 2 last trains = REAL, official table image** via 常州本地宝
  (2025-03-24 table, article updated 2026-08-31; image
  `https://imgbdb4.bendibao.com/czbdb/traffic/20253/24/2025324093559_13697.png`,
  saved as `/tmp/cz_l2_tt.png`). Termini last departures 22:00 both
  directions; per-station lasts transcribed for both directions.
- **First trains (both lines) + Line 1 last trains = 都市圈 dushiquan**
  (Line 1 `jt.dushiquan.net/changzhou/schedule/273.html`,
  Line 2 `.../274.html`, crawled 2026-11-17). First trains are internally
  consistent (trains start simultaneously at 06:00 from several stations,
  same pattern as Jinhua's 发 markers — NOT data errors).

**OPEN QUESTION — Line 1 last trains (+30 min shift)**: dushiquan/icauto
show Line 1 termini last departures 22:00, but the 本地宝 Q&A (2026-08-31)
says the 2025 spring adjustment set Line 1's last to **22:30**, and two
2026 news articles (2026-06-18, 2026-10-24, jsnews.jschina.com.cn)
confirm "1号线始发站末班车保持22:30不变" (Line 1 terminus last train
REMAINS 22:30). Dushiquan's Line 2 lasts are also ~1 min earlier than the
official image for most stations, suggesting dushiquan's data is one
timetable revision stale. **Resolution applied: Line 1 last trains =
dushiquan values + 30 min (both directions)**, so termini last departures
are 22:30 and service ends ~23:29 (22:30 + 57 min end-to-end ≈ 23:27–23:29,
matching the 2025 article's "service ends 23:29"). Line 2 lasts = the
official image values (NOT shifted). If a per-station Line 1 last-train
table is found, replace the shifted values with it.

Operating hours roughly **06:00–23:29** (first departures 06:00, last
arrivals ~23:29 Line 1 / ~22:31 Line 2). Per-station first/last are the
published values for both directions; termini have null for the direction
toward themselves (same convention as Harbin/Dalian/Jinhua).

Historical note: Line 2 丁堰 / 潞城 / 五一路 were temporarily suspended
2022-07-26 → 2022-09-01 for sound-barrier works; fully restored
2022-09-01 — all 15 stations operate now.

## Logo / splash / theme / transit app

- Logo: the official Changzhou Metro mark (`ChangzhouMetro.svg` on
  en.wikipedia.org, file page 53547778). **Download BLOCKED from this VM**
  (upload.wikimedia.org returns HTTP 429 via curl and 403 via browser
  fetch, persistently, even after minutes of waiting). **Fallback used**:
  `logo.b64` is the official **常州地铁Metro app icon artwork** (the white
  logo mark on brand red, 512 px App Store artwork, resized to 120×120
  PNG) — official artwork, unaltered, not redrawn. The app renders the
  logo in a small circle, so this shows as a red circle with the white
  mark. If the SVG becomes downloadable, replace `logo.b64` with the
  mark from `ChangzhouMetro.svg`.
- Splash: the user did NOT send a Changzhou splash. `splash.b64` is a
  **placeholder built from the map image**: a 1170×2532 white portrait
  canvas with the map image scaled to full width and centred vertically
  (the map's white background blends with the canvas). It is NOT a
  designed splash. If the user sends a dedicated Changzhou portrait
  splash, replace `splash.b64` with it (same 1170×2532 pattern as
  Harbin/Dalian/Jinhua).
- Theme: Changzhou Metro brand red = Line 1 colour **#CD5C5C**
  (Wikipedia Template:常州地铁颜色, code 1; the map's red band samples
  ~(200,95,95), matching). Line 2 blue **#529FC9** (same template, code 2;
  the map's blue samples ~(85,158,197), matching). Darker variant for
  selected states/text: **#A04848** (0.78× the brand red, same ratio as
  Jinhua's dark variant). Used for the web `.cz-theme` CSS and the native
  accent/search-button colour.
- Transit jump: **常州地铁Metro** (Changzhou Metro app), by Bwton
  Technology Co., Ltd. (same developer family as Jinhua's 任我行).
  App Store id **1474201266** ("常州地铁Metro", bundle
  com.bwton.msx.czb). No confirmed URL scheme → App Store link, same as
  Harbin/Dalian/Jinhua. Icon `web/czmetro-icon.b64` is the App Store
  artwork (512 px) resized to 120×120.

## Sources

- Operating status, line lengths, opening dates, station lists:
  en.wikipedia.org Changzhou Metro + zh.wikipedia.org 常州地铁,
  常州地铁1号线, 常州地铁2号线 (crawled 2026-11-17); Railway Gazette
  (43 stations, Line 1 2019-09-21, Line 2 2021-06-28).
- Line 5/6 construction status: en.wikipedia.org Changzhou Metro
  (Line 5 started Oct 2023, expected 2028, 25 stations 揽月湾—东青;
  Line 6 started Oct 2024, expected Dec 2029, 21 stations phase 1
  武进沿江城际—建业路）.
- Line colours: zh.wikipedia.org Template:常州地铁颜色
  (1 → #cd5c5c, 2 → #529fc9, via expandtemplates API 2026-11-17).
- Fare: zh.wikipedia.org 常州地铁 + 常州本地宝
  (≤5 ¥2; 5–10 ¥3; 10–15 ¥4; 15–22 ¥5; 22–29 ¥6; >29 ¥6+ceil((km−29)/9);
  full Line 1 34.24 km = ¥7).
- Line 2 last trains: 常州本地宝 official table image
  (2025-03-24 table, article updated 2026-08-31).
- First trains + Line 1 lasts (pre-shift): 都市圈 dushiquan
  jt.dushiquan.net/changzhou/schedule/273.html (Line 1) and 274.html
  (Line 2), crawled 2026-11-17.
- Line 1 22:30 last-train confirmation: 本地宝 Q&A 2026-08-31;
  jsnews.jschina.com.cn 2026-06-18 and 2026-10-24
  ("1号线始发站末班车保持22:30不变").
- 常州地铁Metro App Store id: iTunes Search API (term 常州地铁, CN),
  trackId 1474201266, seller Bwton Technology Co., Ltd.; artwork URL
  is1-ssl.mzstatic.com (downloaded 2026-11-17, 512×512).
- Map image: user's photo
  `F9ACF0B5-2AAA-48B1-B758-7CC296144D39-photo-002884B3-7816-428A-97E7-7CE7F1D69367.jpg`
  (1206×1419, Changzhou metro schematic, Chinese + English labels).

## Verification

Node harness `/tmp/cz-test.js`: **1125 passed, 0 failed** (2026-11-17).
Checks: station counts (43 / 29 / 15), line lists match the official
Wikipedia order, all coordinates in 1206×1419 bounds, L1 south vertical
x=530 (22 stations) and L2 y=681 (15 stations), no duplicate coords/names,
42 edges all consecutive in line order, graph connected (43/43 reachable),
exactly one interchange (文化宫， degree 4), fare band boundaries + the
published ¥7 cross-check, timetable covers all 43 stations with correct
line counts / null termini / first < last / plausible ranges, Line 1
termini lasts 22:30 (+30 applied), Line 2 lasts match the official image,
NO unopened line/station present (Line 5/6 names absent), route colours
match the template, map.svg bytes identical to the user image.
