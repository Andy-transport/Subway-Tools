# Dalian Metro — NOTES (web/dalian/)

Dalian metro support for Subway motion, 5th city (`dl`). 6 operating lines,
**100 unique stations** (see the 100-vs-99 discrepancy below).

## Network (verified 2026-11-15, map + Wikipedia line tables)

| Line | Colour | Stations | Termini |
|------|--------|----------|---------|
| 1 | green `00A651` | 22 | 姚家 → 河口 |
| 2 | blue `0091D9` | 29 | 大连北站 → 海之韵 |
| 3 | magenta `E6007E` | 12 | 大连站 → 金石滩 |
| 3B (3号线支线) | magenta `E6007E` | 7 | 开发区 → 九里 |
| 5 | red `E60012` | 18 | 后关 → 虎滩新区 |
| 12 | purple `7D5BA6` | 8 | 河口 → 旅顺新港 |
| 13 | yellow `F5C400` | 12 | 九里 → 普兰店振兴街 |

Line entries total 108; 8 stations appear twice (7 cross-line interchanges +
开发区 shared between L3 main/branch): 大连北站 (L1+L2), 西安路 (L1+L2),
河口 (L1+L12), 大连站 (L3+L5), 后盐 (L3+L5), 九里 (L3B+L13),
青泥洼桥 (L2+L5), 开发区 (L3+L3B).

Line 3 branch stations: 开发区， 通世泰， 鸿玮澜山， 东山路， 和平路，
十九局， 九里. **通世泰 confirmed** as the branch station name.

**Excluded — NOT operating**: Line 4 (Phase 1, trial operation planned 2027);
Line 13 Phase 2 (11 stations); Line 1 north extension; 梭鱼湾西 (planned,
"暂缓开通"); 地铁海湾基地 (staff-only); 高城山 / 黄海大道 (reserved);
Line 13 reserved stations （平安河， 五里台， 四十里， 五十里， 西三十里）.
后关 is L5-only; 梭鱼湾 is an L5 station, NOT L3.

## Station coordinates (map 1206×1070, Rail Map Painter)

Dot detection: dilate sat-mask ×2 → enclosed white components (180) →
cluster within 11 px (142) → drop credit-text region (x>920,y>960) → 128 dots
(`dots_clustered.json`). Missing/ambiguous dots resolved with a line-profile
dip method (scan a line-colour mask along a straight segment; dips = station
dots) plus targeted map crops at 3×–8× zoom.

**Interpolated (4)**: 西安路 (583,737) — dip-confirmed at the green×blue
crossing, interchange dot undetected; 马栏广场 (524,740), 辽师大 (536,739) —
the map compresses the 马栏广场/辽师大/交通大学 cluster; 交通大学 (548,740)
dot + label-confirmed in a zoom crop.

**Dip-located (20)**, rest detected dots. 河口 = centroid of split fragments
(431,988)+(434,1000.5) → (433,994). 后盐 = (717,464) (large interchange dot;
the dip at 471 is its lower half). 大连站 = (728,690); 青泥洼桥 = (724,736).

**Dropped as false positives**: dots 4, 5, 8, 13 (near L13 大医三院/石河北海/
石河黄旗）; dot at (660,639) on L3 north is a non-station artifact (no station
between 金家街 and 香炉礁）; L12 dip at x=932 is spurious (the line left the row).

## 100 vs 99 stations — discrepancy

Per-line counts verified against Wikipedia + the map sum to **100 unique
stations** (22+29+18+18+8+12 = 107 line entries − 7 cross-line interchanges).
A published source says "地铁覆盖6线99站". The 1-station difference is
unexplained (possibly a counting method or a stale figure); the map +
Wikipedia line tables support 100. Do NOT silently claim 99.

## Map

`map.svg` is a JPEG-in-SVG wrapper (the user's map JPEG embedded), the same
approach as Shanghai's. There is no potrace/autotrace/vtracer on this machine,
so no true vector trace — **zoom sharpness will NOT materially improve** over
the JPEG (same caveat as Shanghai).

## Logo / splash / theme

- Logo: official Dalian Metro mark (blue circle-D-Z) from Wikimedia
  `Logo_of_Dalian_Metro.jpg` (484×206), graphic cropped to a 120×120 square
  (`logo.b64` / `logo.png`). Renders in a 26 px circle, so the square mark
  (not the wide lockup) is required.
- Splash: the user's exact image `splash-user.jpg` (1170×2532; white
  background, black 大连 calligraphy, green Line 1 diagonal in a circle,
  配线查询, DALIAN SUBWAY · TRACK LAYOUT LOOKUP), encoded as `splash.b64`.
- Theme: Dalian Metro brand blue **#0D579A** (median RGB 13,87,154, sampled
  from the official logo). Darker text accent #0a4273. Used for the web
  `.dl-theme` CSS and the native accent/search-button colour. The user can
  change it.
- Transit app jump row: **大连交通e出行** (official, seller Dalian Metro
  Co., Ltd.; App Store id **1383655806**, verified via the iTunes Search API
  2026-11-15). Icon `dalianjiaotong-icon.b64` is the app's App Store artwork
  (blue 大连交通 calligraphy). Label "打开大连交通e出行". No confirmed URL
  scheme, so the App Store page is the link (same as the other cities).

## Fare — VERIFIED

Distance-based (bendibao / Dalian metro fare standard):
¥2 ≤6 km; ¥3 6–12; ¥4 12–18; ¥5 18–26; ¥6 26–34; ¥7 34–44; ¥8 44–54;
beyond 54 km +¥1 per 15 km.
Cross-checked: 普兰店振兴街–九里 ¥7; 普兰店振兴街–大连站 ¥10;
普兰店振兴街–金石滩 ¥10 (all match the published table).

Fare is computed from the map with per-line px/km scales (solved from the
real line lengths over the map pixel path; the schematic compresses the long
intercity lines, so a single scale would be far off):
L1 24.36, L2 27.37, L3 13.77, L3B 9.22, L5 23.40, L12 8.31, L13 9.30
(fallback 16.53). Real lengths used: L1 28.34 km, L2 37.3, L3 49.15,
L3B 14.3, L5 24.48, L12 40.35, L13 42.9. L3 main/branch split from the
63.45 km total; L12/L13 lengths are approximate — fares are estimates.

## Timetable (`web/timetable/dl.json`, 100 stations)

- **L1 REAL** — TravelChinaGuide per-station table (updated 2026-08-25).
- **L2 REAL** — TravelChinaGuide (updated 2026-08-27). Bendibao's 春柳 page
  is outdated/wrong (contradicts TCG; its last-train time precedes the
  terminus departure) — TCG trusted.
- **L3 REAL** — bendibao weekday per-station image table. Weekend read too:
  identical except first trains from 金石滩/小窑湾/双D港 are 15 min later on
  weekends (6:30/6:39/6:42 vs 6:15/6:24/6:27). Through-train 金石滩 times
  used for the 金石滩 direction. **保税区 short-turn**: 大连站→保税区 last
  21:30 vs →金石滩 19:30 — documented here, not in the 2-direction format,
  except 大连站 itself carries both `金石滩 06:00/19:30` and
  `保税区 06:00/21:30`. Discrepancy: 金石滩→大连站 last is 20:30 per the
  bendibao image vs 19:30 per dushiquan — bendibao image trusted.
- **L3B REAL** — dushiquan per-station table (九里→开发区 06:00/20:00;
  开发区→九里 06:00/20:13).
- **L5 ESTIMATED** — distance interpolation (Wikipedia Line 5 cumulative km;
  verified anchors: 后关→虎滩新区 05:30/22:00, 虎滩新区→后关 06:00/22:30,
  大连站→虎滩新区 05:53/22:23, 大连站→后关 06:14/22:44; rates 1.386 min/km
  north of 大连站， 1.774 min/km south). Flagged as estimated in-app.
- **L12 REAL** — dushiquan per-station table, except **旅顺 interpolated**
  (06:37/21:02 to 旅顺新港， 06:23/21:03 to 河口 — dushiquan's table
  duplicates 旅顺新港 and omits 旅顺）.
- **L13 REAL** — dushiquan per-station table (九里→普兰店振兴街 06:46/19:53;
  普兰店振兴街→九里 06:30/19:30; full trip ~46 min).

**L2 first-train anomaly**: 辛寨子/机场/虹港路/虹锦路 westbound first times
(05:33/05:48/05:46/05:44) reflect depot-originating trains and don't fit a
single 海之韵 departure; used as published by TCG.

## Files

- `web/dalian/stations.json` (100 entries, {n,py,ini,x,y})
- `web/dalian/routes.json` (lines 1,2,3,3B,5,12,13; branch = separate line 3B)
- `web/dalian/map.svg` (JPEG-in-SVG wrapper, 184,556 B)
- `web/dalian/logo.b64` (20,688 chars), `logo.png` (120×120)
- `web/dalian/splash.b64` (user's exact splash-user.jpg)
- `web/dalian/build_stations.py`, `build_timetable.py`
- `web/timetable/dl.json` (100 stations)
- `web/dalianjiaotong-icon.b64` (大连交通e出行 App Store icon)
- Scratch: `dots_*.json`, `tt-l3-*.png`, `v-*.png`, `ann-*.png`, tiles/zooms
