# Harbin Metro — 4th city ('hb')

Source map: user's Metro Pro 哈尔滨地铁线网图 2026.08 (`map-user.jpg`, 1053×1620).
Scope: the 3 operating lines only (1, 2, 3). No planned lines.

## Lines / stations (73 unique, 5 interchanges)

| Line | Colour (map) | Stations | Termini / shape |
|---|---|---|---|
| 1 | red #C00030 | 23 | 哈尔滨东站 – 新疆大街 |
| 2 | green #108040 | 19 | 江北大学城 – 气象台 |
| 3 | yellow #F0C040 | 36 | loop (closed; first=last neighbour edge added) |

Interchanges (5): 博物馆 (1/2), 太平桥 (1/3), 医大二院 (1/3), 人民广场 (2/3), 珠江路 (2/3).
Line 3 is a full loop (closed 2024-11). Its timetable dirs are 内环 / 外环 (same as Beijing Line 2).

Station names/order verified against zh.wikipedia 哈尔滨地铁1号线 / Template:哈尔滨地铁车站 /
travelchinaguide (2026-10-20). The map (2026.08) agrees with all three.

## Coordinates

Method: station-label detection (dark text blobs within 30px of a line, clustered
into labels; dot = nearest line pixel to the label centroid), merged within 12px.
126 label clusters -> 95 -> 80 after title/legend exclusions -> R 21 / G 19 / Y 36
after merging. Interchange positions are NOT the label dots: they are the computed
line crossings (minimise dist-to-line-A + dist-to-line-B in a tight window),
because labels at interchanges are displaced 30–80px along the line.

- 博物馆 (R×G): (527, 714). 太平桥 (R×Y): (618, 565). 医大二院 (R×Y): (437, 1016).
  人民广场 (G×Y): (389, 639). 珠江路 (G×Y): (698, 825).
  (An earlier 珠江路 estimate (695, 903) was WRONG — a stray green pixel, not Line 2;
  the tight-window recompute gives (698, 825), with 44 green + 59 yellow px nearby.)

Interpolated (no detected dot; linear between same-line neighbours):
- 黑龙江大学 (L1): (434, 994.5), between 理工大学 (431, 973) and 医大二院 (437, 1016).
- 渤海路 (L1): (517.5, 1443), between 镜泊路 (512, 1345) and 新疆大街 (495, 1481).
  (The earlier plan also listed 镜泊路 as interpolated; it was in fact detected —
  (512, 1345) — so only the two above are interpolated.)

Dot-detection caveat: this Metro Pro map draws station dots that blend into the
line (thin ~5px pale JPEG strokes), so pure dot/width detection failed
(7 white-disc dots; 19 distance-transform peaks; 38 opening blobs with many
false positives). The label-cluster method is what produced the coordinates.
Spot-checks: 哈尔滨东站 / 新疆大街 termini, 博物馆 crossing, and the Line 2
river crossing (冰雪大世界 (258,606) before 太阳岛 (334,592) by line density)
were verified against the map geometry.

## Fare (verified)

Distance-based, same bands as Shenyang (Wikipedia 哈尔滨地铁 + 哈尔滨本地宝,
agreeing): 0–6km ¥2, 6–10km ¥3, 10–14km ¥4, 14–21km ¥5, 21–28km ¥6,
28km+ +¥1 per 10km. No cap in the official table; network max (~32km loop) = ¥7.
Implemented in template.html routeFare ('hb' branch) using coordinate distance
(segKm with the Harbin px/km scale below).

px/km scale, solved from real line lengths over the map pixel path:
L1 26.3km / 1156px = 43.94; L2 28.7km / 1195px = 41.64; L3 32.2km / 1645px = 51.08.
Overall 45.82. Implemented per-line in shScaleFor ('hb' branch).

## Timetable (ESTIMATED — not verified per station)

web/timetable/hb.json. Operating hours verified: 05:30–22:30 for all three lines
(哈尔滨本地宝: 自2025-05-06首班车由6时调整为5时30分; travelchinaguide Line 1
termini 05:30–22:30). Per-station first/last are ESTIMATED: termini 05:30/22:30,
+2 min per stop along the line (matches the verified Line 1 sample: 桦树街
05:31/22:31 toward 新疆大街, 05:36/23:14 toward 哈尔滨东站). Terminus toward
itself = null (same convention as bj.json). Line 3 loop: 内环/外环 dirs; first
内环 train passes 太平桥 05:30, each stop +2 min; 外环 the reverse. The web
timetable tab shows a note that Harbin times are estimates. Replace with the
official per-station timetable when available.

## Theme / transit app

- Theme colour: Harbin brand RED #C00030 (sampled from the metro logo / Line 1;
  user: 主题色也是红色). Dark variant #8A0020 for text. Native tab-bar selected
  state and search button use harbinRed in Harbin mode. Distinct from Shanghai
  red #E60012 (Harbin is deeper/darker).
- Transit-app jump row: 打开哈尔滨城市通 (user: 跳转哈尔滨城市通).
  App Store id 1448467024, verified via iTunes Search API 2026-11-15
  (哈尔滨城市通, Harbin City Smart Card Co., Ltd, com.bm.nfccitycard.app).
  No confirmed URL scheme, so the App Store page is the link (same as the
  other three cities). Icon: the app's own App Store artwork (512px), rounded
  to 120×120 PNG in web/harbinchengshitong-icon.b64.

## Splash / logo

- Splash: the USER-SUPPLIED image web/harbin/splash-user.jpg (1170×2532 JPEG:
  white background, blue 哈尔滨 calligraphy, yellow Line 3 loop in a circle,
  配线查询, HARBIN SUBWAY · TRACK LAYOUT LOOKUP), encoded as splash.b64.
  Used for both the web splash and the native SplashHB.jpg. Do NOT regenerate.
- Logo: red circular Harbin metro logo cropped from the map title box
  (x604–653, y94–142, ~49px), white made transparent, 120×120 PNG in
  logo.b64 and app/HarbinLogo.png.

## Files

- web/harbin/stations.json (73), routes.json (3 lines, 76 edges), map.svg
  (JPEG-in-SVG wrapper, 1053×1620 — same as Shenyang/Shanghai; no
  potrace/autotrace/vtracer on this machine, so NOT a true vector trace),
  logo.b64, splash.b64, splash-user.jpg, map-user.jpg, NOTES.md, work/ (dots).
- web/timetable/hb.json (73 stations, estimated — see above).
- web/harbinchengshitong-icon.b64 (哈尔滨城市通 App Store artwork).
- Wiring: web/build_offline.py (step Q + hb timetable + hbct icon),
  web/template.html (HB globals, hb-theme, switchCity, fare, scale, timetable,
  transit row), app/AppDelegate.swift (harbinRed, city menu, splash, transit
  id), build.sh (SplashHB.jpg + HarbinLogo.png).
