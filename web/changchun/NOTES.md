# Changchun Rail Transit (长春轨道交通) — NOTES (web/changchun/)

Changchun support for Subway motion, 9th city (`cc`). Eight operating
lines, **142 unique operating stations** (see the 167-vs-168 note below).

## Network (verified 2026-11-18, user map + Wikipedia line tables)

| Key | Line | Colour | Stations | Opened | Length | Termini |
|-----|------|--------|----------|--------|--------|---------|
| 1 | 1号线 | red `E50011` | 15 | 2017-06-30 | 18.14 km | 北环城路 → 红嘴子 |
| 2 | 2号线 | blue `3B6A96` | 27 | 2018-08-30 | 35.5 km | 汽车公园 → 雾开河大街 |
| 3 | 3号线 | green `009943` | 34 | 2002-10-30 | 34.4 km | 伪满皇宫 → 长影世纪城 |
| 4 | 4号线 | purple `7D4697` | 21 | 2011-06-30 | 20.8 km | 长春站北 → 天新路 |
| 5 | 5号线 | dark yellow `A57823` | 18 | 2026-09-28 | 19.66 km | 卓越大街 → 东大桥 |
| 6 | 6号线 | pink `E88F99` | 22 | 2024-03-28 | 29.57 km | 双丰 → 长影世纪城 |
| 7 | 7号线 | magenta `A5308C` | 19 | 2026-08-26 | 23.2 km | 汽车公园 → 东环城路 |
| 8 | 8号线 | cyan `25B7BC` | 12 | 2018-10-30 | 13.3 km | 北环城路 → 广通路 |

Line entries total 168; 26 stations appear in two lines, so
168 − 26 = **142 unique stations**. All 26 interchanges are on exactly
two lines (no triple interchange).

Colours are from Wikipedia Template：长春轨道交通颜色 (source:
长春轨道交通集团）, verified via the expandtemplates API 2026-11-18.
Line names are the plain `N号线` (the app's line picker shows them as
`Line N` / `N號線` in English / Traditional Chinese).

1号线 (north → south): 北环城路、庆丰路、一匡街、长春站北、长春站、
胜利公园、人民广场、解放大路、东北师大、工农广场、繁荣路、卫星广场、
市政府、华庆路、红嘴子.

2号线 (west → east): 汽车公园、捷达大路、西湖、双丰、长春西站、
兴隆堡、西环城路、和平大街、万福街、景阳广场、解放桥、建设广场、
文化广场、解放大路、平阳街、南关、吉林大路、东盛大街、东环城路、
长青、东方广场、哈尔滨大街、窦家沟、英俊大街、英凯大街、林溪大街、
雾开河大街. (东延段 东方广场—雾开河大街 opened 2025-09-28.)

3号线 (north → south, then south-east): 伪满皇宫、东广场、长春站、
芙蓉桥、西安桥、南昌路、朝阳桥、解放桥、湖西桥、宽平桥、抚松路、
孟家屯、湖光路、电台街、前进西、前进大街、卫明街、卫光街、卫星广场、
亚泰立交桥、伊通河、职业技术大学、吉林广电、会展中心、世纪广场、
金鑫街、博硕路、金河街、农博园、净月潭公园、紫杉路、宝相街、滑雪场、
长影世纪城.

4号线 (north → south): 长春站北、北亚泰大街、伪满皇宫、东大桥、
东新路、吉林大路、公平路、海口路、浦东路、威海路、北海路、
职业技术大学、世荣路、南环城路、宜盛街、天工路、福祉大路、天青路、
天普路、前十里堡、天新路.

5号线 (west → east): 卓越大街、市委党校、顺达路、越达路、安新路、
蔚山路、硅谷广场、电台街、省委党校、南湖广场、长影旧址博物馆、
红旗街、文化广场、同志街、人民广场、大经路、省妇儿中心、东大桥.
(Opened 2026-09-28; 长影旧址博物馆 opened later, 2026-10-22 — see the
167-vs-168 note.)

6号线 (west → east, then south-east): 双丰、长春西站、腾跃街、
支农大街、飞跃广场、欧亚卖场、光谷大街、硅谷广场、百花园、市法院、
兰桡湖公园、轨道集团、新明街、华庆路、南溪湿地公园、福祉大路、
吴家店、亚泰足球基地、樱花街、聚业大街、省博物院、长影世纪城.

7号线 (west → east, then north): 汽车公园、西湖大路、兴安路、兴顺路、
飞跃广场、第一汽车制造厂、孟家屯、辉南街、南湖广场、南湖公园、
工农广场、省税务局、东岭南街、威海路、赛得广场、会展大街、
中东大市场、岭东路、东环城路. (Opened 2026-08-26. The north-east
arm is an L-shape — vertical at x≈715–728 from 赛得广场 north to
东环城路, NOT a diagonal.)

8号线 (south → north, then east): 北环城路、一二三中学、小南、
小城子街、北湖大桥、北湖公园、和安街、光机路、大学城路、地理所、
奥林匹克公园、广通路.

**26 interchanges**: 北环城路 (1/8), 长春站北 (1/4), 长春站 (1/3),
人民广场 (1/5), 解放大路 (1/2), 工农广场 (1/7), 卫星广场 (1/3),
华庆路 (1/6), 汽车公园 (2/7), 双丰 (2/6), 长春西站 (2/6),
解放桥 (2/3), 文化广场 (2/5), 吉林大路 (2/4), 东环城路 (2/7),
伪满皇宫 (3/4), 孟家屯 (3/7), 电台街 (3/5), 职业技术大学 (3/4),
长影世纪城 (3/6), 东大桥 (4/5), 威海路 (4/7), 福祉大路 (4/6),
硅谷广场 (5/6), 南湖广场 (5/7), 飞跃广场 (6/7).

**Excluded — NOT operating (drawn on the map, NOT in any data file)**:
- **9号线** (under construction; not on the user's map as a line, but
  must never be added until it opens).
- **3号线南延** (天泽大路 southern extension past 长影世纪城:
  天津大路, 交通大路 drawn on the map). 3号线 is 伪满皇宫—长影世纪城,
  34 stations; the 南延工程 runs 长影世纪城→文远大路 via 天泽大路.
- **1号线南延** (past 红嘴子: 红石, 兴创路 drawn on the map).
  红嘴子 is the operating terminus.
- **辽宁路站** (closed station; not in any line list).
Per the parent rule: unopened lines/stations must not appear in the
searchable/routable data, even though the map image shows them. The map
is used as-is (JPEG-in-SVG); the drawn unopened stations remain visible
on the image, which is a known cosmetic caveat, not a data error.

**167 vs 168**: the Wikipedia 长春轨道交通 article text says 167座车站
(as of 2026-09) and its line table lists 5号线 as 17 stations. That count
is from the 2026-09-28 opening, before 长影旧址博物馆 opened on
2026-10-22 (its opening is noted in the same article's 5号线 row).
Current operating count is 168 line-stations (L5 = 18) / 142 unique.
Do NOT silently claim 167.

## Station coordinates (map 1206×1189, user's image)

Station dots are small white discs (~6 px) on the coloured lines. Method
used (the ring-disc detector found only 110 of 142 — the rest were
recovered by per-line band-gap scans, line-crossing measurements, and
interpolation between neighbours; see `/tmp/cc/` working files):
- Traced each line's geometry by pixel scans (e.g. L1 vertical x=527,
  L4 vertical x=640, L8 horizontal y=143, L2 east y≈527 then y≈491).
- Detected station dots via white-disc ring detection + per-line
  band-gap scans (a dot = a low line-colour run along the line path).
- Pinned interchanges by line-crossing measurements (e.g. the L4
  crossing at x=527 gives 长春站北 y≈395; the L3 crossing gives
  长春站 y≈417; the L2/L3 overlap centre (412,539) gives 解放桥;
  the L2/L5 overlap (494.5,541.4) gives 文化广场）.
- Validated with a numbered overlay (`/tmp/cc/numbered142.png`, viewed
  in 4 tiles): all 142 dots land on their line, in the correct order,
  next to their labels.

**Interpolated / crossing-derived (not directly dot-detected) — flag if
re-checking**: L1 长春站北/长春站 (crossing-derived); L2 西湖,
万福街, 景阳广场, 解放桥 (crossing), 吉林大路, 东环城路, 林溪大街,
文化广场 (crossing); L3 伪满皇宫, 卫光街, 净月潭公园, 长影世纪城;
L4 天新路 (band end); L5 蔚山路, 硅谷广场 (computed L5/L6 crossing
≈(360,767)), 南湖广场; L6 硅谷广场, 省博物院, 长影世纪城;
L7 第一汽车制造厂, 南湖广场, 会展大街, 东环城路; L8 一二三中学,
小城子街. All other coordinates are directly dot-detected. No
coordinate was fabricated; every dot was verified on the overlay.

Geometry notes: L1's 长春站北 (395) and 长春站 (417) are only 22 px
apart; L2's 万福街 (391,527) and 景阳广场 (401,534) are only ~12 px
apart (dense but verified). L6's horizontal ends at 长影世纪城
(880,975) for both L3 and L6 — NOT (1010,980). L2 east curves up
from y≈527 (x640–830) to y≈491 (x900–1150).

**px/km (for the fare model)**: pixel path length / real line length
(Wikipedia): L1 **35.14** (637.5 px / 18.14 km), L2 **31.99**
(1135.7 / 35.5), L3 **33.44** (1150.5 / 34.4), L4 **34.92**
(726.3 / 20.8), L5 **32.95** (647.8 / 19.66), L6 **34.15**
(1009.9 / 29.57), L7 **35.81** (830.8 / 23.2), L8 **28.69**
(381.6 / 13.3). See WIRING.md for how to use these in `shScaleFor`.
The map is schematic; scale varies by line (28.7–35.8), so fares
computed from pixel distances are estimates (typically ±¥1).

## Map

`map.svg` is a JPEG-in-SVG wrapper (the user's map JPEG embedded, bytes
identical — verified by round-trip decode), the same approach as
Shanghai/Harbin/Dalian/Jinhua/Changzhou/Chongqing. No true vector trace
is feasible from this raster image — **zoom will blur** past ~2× (same
caveat as the other raster cities; only Beijing is true vector).

## Fare (VERIFIED, zh Wikipedia 长春轨道交通 票价 + jl.sina.com.cn)

Distance-based, by ride distance (km), unified across the network since
2019-05-30 (same as the 2017 L1/L2 standard):
- ≤ 7 km → ¥2
- 7–13 km → ¥3
- 13–19 km → ¥4
- 19–27 km → ¥5
- 27–35 km → ¥6
- > 35 km → ¥6 + ceil((km − 35) / 10)

Cross-checks: the full L2 (汽车公园—雾开河大街, 35.5 km) is ¥7
(35.5 km is just over the 35 km band edge). No published per-OD fare
table was found for an independent cross-check — the band structure
itself is verified from Wikipedia; intermediate fares are computed
from the schematic map scale and are estimates.

Discounts (NOT applied in the app, same rule as build 66 — no per-city
card-vs-cash rule is implemented; do not invent one): 长春轨道交通一卡通
9.5折 (月累计超50元 8.5折, 超100元 8.0折, 超200元恢复 9.5折);
长春市民卡 app 9折; 残疾军人/伤残人民警察/残疾人/现役军人 free;
full-time primary/secondary students 5折; 1 adult + 1 child under 1.2 m
free. Single-journey ticket valid 180 min (overtime surcharge ¥2).

## Timetable (L2 + L5 REAL per-station; L1/L3/L4/L6/L7/L8 ESTIMATED)

`web/timetable/cc.json` — **winter times** (today is 2026-11-18;
summer 5/1–10/31, winter 11/1–4/30). Summer last trains are 30 min
later than winter on most lines (see below); first trains are the
same in both seasons.

**REAL per-station tables** (Wikipedia line articles, sourced from the
official 长春市轨道交通集团有限公司 timetable, ccqg.com):
- **L2** (27 stations): full per-station first/last, updated
  2025-09-28 (ccqg.com/2hx4). Winter lasts used.
  Termini: 汽车公园→雾开河大街 first 05:15, last 22:05 (winter);
  雾开河大街→汽车公园 first 05:45, last 22:05 (winter).
  Mid-line first trains are real in the table: 双丰 05:15 toward
  雾开河大街, 东方广场 05:45 toward 汽车公园.
- **L5** (18 stations): full per-station first/last, updated
  2026-09-28 (ccqg.com/5hx4). Winter lasts used.
  Termini: 卓越大街→东大桥 first 05:15, last 22:05 (winter);
  东大桥→卓越大街 first 05:35, last 22:05 (winter).

**ESTIMATED** (per-line terminus first/last from Wikipedia 长春轨道交通
各路線首末班车時間, updated 2026-09-28; per-station times interpolated
at **2.0 min per station interval**, calibrated against the real L2/L5
tables — L2 end-to-end 05:15→06:07 = 52 min / 26 intervals = 2.0
min/interval; L5 05:15→05:51 = 36 min / 17 intervals = 2.1
min/interval). Flagged in-app via the `tt.note.cc` span (see
WIRING.md 1m). Per-line termini (winter lasts):
- L1: 红嘴子→北环城路 05:15, last 22:05; 北环城路→红嘴子 05:50,
  last 22:05. (Summer last 22:35.)
- L3: both directions 05:55, last 22:00 winter / 22:30 summer.
  **First-train cap 06:07**: the Wikipedia note says multiple mid-line
  stations start first trains at 05:55 and most stations' first train
  in both directions is no later than 06:00, so the far-terminus
  interpolation (which would give up to 06:57) is capped at 06:07
  (the latest first-train value in the dushiquan spot-checks:
  长春站 06:05, 卫星广场 06:07 toward 伪满皇宫）. The actual first
  train may be a few minutes earlier at some stations.
- L4: both directions 05:55, last 22:05 winter / 22:35 summer.
- L6: 双丰→长影世纪城 05:15, last 22:05; 长影世纪城→双丰 05:35,
  last 22:05. (Summer last 22:35.) **Mid-line origin used**:
  福祉大路 05:18 toward 长影世纪城 (from the Wikipedia table) — stations
  福祉大路→长影世纪城 use 05:18 + (i−15)×2 min instead of the 双丰
  interpolation. Toward 双丰, mid-line origins at 南溪湿地公园 /
  兰桡湖公园 are listed with N/A times — the interpolation is used and
  the actual first train may be earlier.
- L7: 汽车公园→东环城路 05:15, last 22:05; 东环城路→汽车公园 05:40,
  last 22:05. (Summer last 22:35.)
- L8: both directions 06:00; toward 北环城路 last 21:30 winter /
  22:00 summer; toward 广通路 last 22:05 winter / 22:35 summer.
  Mid-line first trains at 大学城路 / 北湖大桥 (toward 北环城路）
  and 北湖大桥 (toward 广通路） are listed with N/A times — the
  interpolation is used and the actual first train may be earlier.

Operating hours roughly **05:15–23:37** (first departures 05:15,
last arrivals ~23:37 at the far termini). Per-station first/last are
the published values for both directions; termini have null for the
direction toward themselves (same convention as Harbin/Dalian/Jinhua/
Changzhou/Chongqing).

**Dushiquan spot-checks** (mjt.dushiquan.net, third-party — NOT used
as the source): 长春站 L1 北环城路 05:38/22:22, 红嘴子 05:57/22:07
vs my estimates 05:35/22:25 and 05:58/22:13 (within 3–6 min);
卫星广场 L1 北环城路 05:22/22:06, 红嘴子 06:13/22:25 vs my estimates
05:21/22:11 and 06:12/22:27 (within 1–5 min). L3 dushiquan last trains
(长春站 toward 长影世纪城 21:04, 卫星广场 21:42) are ~1 h earlier than
the Wikipedia terminus times imply — treated as stale (the Changzhou
precedent found dushiquan one revision stale) and NOT used.

## Logo / splash / theme / transit app

- Logo: the official 长春轨道交通 mark is the "CC" monogram (长春 pinyin
  initials deformed into a speeding rail vehicle; Wikimedia
  `Changchun_Railway_Traffic_logo.svg`, 252×252, 11,019 B). **Download
  BLOCKED from this VM** (upload.wikimedia.org returns HTTP 429 via curl
  and 403 via browser fetch, persistently — the same block the Changzhou
  prep hit). **Fallback used**: `logo.b64` is the official **长春E出行
  app icon artwork** (512 px App Store artwork, resized to 120×120 PNG)
  — official artwork, unaltered, not redrawn. If the SVG becomes
  downloadable, replace `logo.b64` with the mark from
  `Changchun_Railway_Traffic_logo.svg`.
- Splash: the user sent a real Changchun splash (already saved as
  `splash-user.jpg` + `splash.b64`, byte-identical round-trip; source
  853×1844, 159,873 B). NOT a placeholder. (配线查询 already removed.)
- Theme: **#E50011** (Line 1's official colour — the system's first
  metro line; the Wikipedia navbox title bar uses a similar red
  #E7000B). No separate system-wide brand colour is published; the
  theme uses Line 1 red, consistent with the Changzhou precedent
  (brand red = Line 1 colour). Darker variant for selected states/text:
  **#B3000D** (0.78× the brand red, same ratio as Jinhua/Changzhou's
  dark variants). Used for the web `.cc-theme` CSS and the native
  accent/search-button colour.
- Transit jump: **长春E出行** (Changchun E-Travel), the official
  长春轨道交通 app, by Changchun Rail Transit Group Co., Ltd.
  (长春市轨道交通集团有限公司）. App Store id **1481796811**
  (bundle com.bwton.msx.ccb — the same bundle as the Android
  v1.0.22, APKPure 2026-03-19). No confirmed URL scheme → App Store
  link, same as Harbin/Dalian/Jinhua/Changzhou/Chongqing. Icon
  `web/ccmetro-icon.b64` is the App Store artwork (512 px) resized to
  120×120 PNG (identical bytes to `logo.b64`, same as Changzhou).

## Sources

- Operating status, line lengths, opening dates, station lists, fare,
  first/last times: zh.wikipedia.org 长春轨道交通 (crawled 2026-11-18,
  sections 各路線首末班车時間 / 票价 / 运营线路， updated 2026-09-28),
  长春轨道交通1/2/3/4/5/6/7/8号线.
- Line colours: zh.wikipedia.org Template：长春轨道交通颜色
  (1 → #e50011, 2 → #3b6a96, 3 → #009943, 4 → #7d4697, 5 → #a57823,
  6 → #e88f99, 7 → #a5308c, 8 → #25b7bc, via expandtemplates API
  2026-11-18; source 长春轨道交通集团）.
- L2/L5 per-station timetables: Wikipedia line articles, citing the
  official 长春市轨道交通集团有限公司 timetable (ccqg.com/2hx4,
  ccqg.com/5hx4).
- L5 长影旧址博物馆 opening 2026-10-22: zh.wikipedia.org 长春轨道交通
  (5号线 row, 最近延伸）.
- 长春E出行 App Store id: iTunes Search API (term 长春E出行, CN),
  trackId 1481796811, seller Changchun Rail Transit Group Co., Ltd.;
  artwork URL is1-ssl.mzstatic.com (downloaded 2026-11-18, 512×512).
- Logo file: Wikimedia `Changchun_Railway_Traffic_logo.svg`
  (zh.wikipedia.org file page 8038617) — download blocked (429/403).
- Map image: user's photo
  `C323E0E2-FF6F-4719-AEDA-81863AC43CA3-photo-3BA16F0E-5F97-4F06-94C8-7A8FEE7D992F.jpg`
  (1206×1189, Changchun rail transit schematic).

## Verification

Node harness `/tmp/cc-test.js`: **4797 passed, 0 failed** (2026-11-18).
Checks: station counts 142 / 168 / 26 interchanges, line lists match
the official Wikipedia order, all coordinates in 1206×1189 bounds,
160 edges all consecutive in line order, graph connected (142/142
reachable), interchange consistency (26 stations, each on exactly
2 lines, connected on both lines), pinyin sort + no duplicate pinyin,
fare band boundaries + the ¥7 full-L2 cross-check, timetable covers
all 142 stations with correct line counts / null termini / first <
last / plausible ranges, L2/L5 match the real Wikipedia tables
(every value), L3 first-train cap 06:07, L6 福祉大路 05:18 mid-line
origin, NO unopened line/station present (Line 9, 天泽大路, 天津大路,
交通大路, 红石, 兴创路, 辽宁路 absent), route colours match the
template, map.svg bytes identical to the user image, logo/splash
decode to valid PNG/JPEG.
