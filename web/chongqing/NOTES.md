# Chongqing Rail Transit (重庆轨道交通) — NOTES (web/chongqing/)

Chongqing support for Subway motion, 7th city (`cq`). **282 unique operating
stations** on 14 operating line keys (16 keys counting the 3 branches).
Data prep completed 2026-11-17. DATA PREP ONLY — not wired into the app.

Source map: `~/workspace/user/files/90D7A510-...-photo-6CCCA7EC-...jpg`
(1206×1111, Chongqing Rail Transit System Plan, Chinese + English labels,
line-colour legend bottom right).

## Network (verified 2026-11-17, user map + zh Wikipedia 重庆轨道交通
## + per-line articles, parsed via MediaWiki API)

| Key | Line | Colour | Stations | Termini |
|-----|------|--------|----------|---------|
| 0 | 环线 (Loop) | gold `E0B754` | 33 | closed ring (重庆西站 → … → 华龙 → 重庆西站) |
| 1 | 1号线 | pomegranate `D7293C` | 25 | 朝天门 → 璧山 |
| 2 | 2号线 | green `1B6E40` | 25 | 较场口 → 鱼洞 |
| 3 | 3号线 | dark blue `1A49A5` | 39 | 鱼洞 → 江北机场T2航站楼 |
| 3B | 3号线空港支线 | dark blue `1A49A5` | 7 | 碧津 → 举人坝 |
| 4 | 4号线 | orange `CD8142` | 32 | 石马河立交 → 黄岭 |
| 5 | 5号线 | light blue `38A2D2` | 32 | 悦港北路 → 跳磴 |
| 6 | 6号线 | pink `E68099` | 28 | 茶园 → 北碚 |
| 6B | 6号线国博支线 | light pink `EA9DB2` | 13 | 礼嘉 → 沙河坝 |
| 6C | 6号线东站支线 | pink `E68099` | 4 | 刘家坪 → 重庆东站 |
| 9 | 9号线 | maroon `862843` | 29 | 高滩岩 → 花石沟 |
| 10 | 10号线 | purple `4B267A` | 26 | 兰花路 → 王家庄 |
| 15 | 15号线 | express blue `2565A7` | 18 | 井口 → 两江影视城 |
| 18 | 18号线 | teal `65CDC4` | 19 | 富华路 → 跳磴南 |
| JT | 江跳线 | blue `1E5CA9` | 7 | 跳磴 → 圣泉寺 |
| BT | 璧铜线 | blue `1C589A` | 8 | 铜梁西 → 璧山 |

Line-station entries total 345 (33+25+25+39+7+32+32+28+13+4+29+26+18+19+7+8);
282 unique stations; **57 interchanges** (stations on 2+ line keys, counting
the 3 branch junctions 碧津 3+3B, 礼嘉 6+6B, 刘家坪 6+6C as transfers).
Branch lines share their parent colour except 6B, which has its own lighter
pink `EA9DB2` (the map draws 国博支线 in light pink, distinct from 6号线
pink `E68099`). JT/BT/3 are all similar blues — user can correct if the
official shades differ.

Full line orders are in `routes.json` (and `_lines.json`, working copy).

**Recent openings included** (all verified): 15号线 opened 2026-11-12
(18 stations, 井口—两江影视城）; 4号线西延 opened 2026-02-10 (石马河立交—
嘉州路 8 stations); 歇台子 (18号线） opened 2025-06-26; 6号线东站支线
opened 2025-06-27; 璧铜线 opened 2025-01-02; 玉河沟 (5号线） opened
2025-07-15.

## Excluded — NOT operating (must NOT enter stations.json / routes.json /
## timetable, per the user's rule 未开通的线路不要加入搜索系统)

- 顺水寺公园 (4号线， unopened; the map legend misspells it 歇水寺公园 —
  official sources unanimously say 顺水寺公园）.
- 新桥 + 邮轮母港 (9号线， unopened).
- 南坪 on 10号线 ONLY (deferred since 2023-11-30, still unopened).
  南坪 REMAINS operating on 3号线 and IS in the data (3号线 only).
- 15号线二期 west extension (9 stations, 15 only): 曾家， 重庆城市管理职业
  大学/职业学院 (same station, renamed), 重庆科技大学， 重庆电子科技职业
  大学， 陈家桥 (陈家桥 IS operating on 1号线）, 大学城北一路， 龙安路，
  张家湾， 五云新城.
- 18号线北延伸段 (19 stations on 18 only; 太平冲/弹子石/小什字/七星岗
  are operating on OTHER lines, so only their 18号线 membership is
  excluded): 石坪镇， 玉峰山， 石坪南， 五里坪， 唐栋新城， 太平冲， 鸡冠石，
  大佛寺， 富民路， 弹子石， 野猫溪， 小什字， 凯旋路， 十八梯， 七星岗，
  重庆站， 菜袁路， 黄沙溪， 大坪西.
- 几江 + 鼎山 (江跳线 south extension, unopened). Their dots ARE drawn on
  the map at (110,1047) and (110,1080) — visible in the image, excluded
  from data.
- 青龙湖 (璧铜线， 暂缓开通）.
- ALL of 7号线， 17号线， 24号线， 27号线 (entirely under construction).
- 鹿山 (10号线） IS operating (opened 2017-12-28). The map legend note
  about an unopened station is about 南坪， not 鹿山 (verified at 3× zoom).

## Station names — corrections and notes

- 跳磴南 (not 跳蹬南 — the Wikipedia master list has a typo; 跳磴 is the
  correct character, confirmed by the line article and the map).
- 江津高铁 (JT line article + map label). The master list and some sources
  say 江津高铁站 — use 江津高铁， note the alternate here.
- 巴滨路湿地公园 is the official name (not 巴滨路）.
- 重庆北站南广场 (Loop/3/10) and 重庆北站北广场 (4/10) are DIFFERENT
  adjacent stations on Line 10 — kept as separate stations with a Line 10
  edge between them. Do NOT merge.
- 重庆西站 carries a stray code `12|01` in the Wikipedia master list (data
  artifact — ignore; it is Loop + 5 only).
- 南湖 is a Loop + 10 interchange (codes 0|26 and 10|02).
- 园博中心 (5号线） vs 园博园 (3号线）: DIFFERENT stations with different
  names, both operating. Line tables on each side claim a transfer, but
  they are not the same station. Treat as a virtual / different-name
  transfer (not routable, per the Beijing precedent); document here.
  Do NOT merge them into one station.

## Interchanges — transfer status

All 57 interchanges were verified against the line tables (a station is an
interchange only if it appears in 2+ operating line tables). Out-of-station
transfers （站外换乘, from the map legend, verified at 2–3× zoom): 玉带山
(Loop/4), 歇台子 (1/5/18), 杨家坪 (2/18), 观音桥 (3/9). Same-name station,
one entry in stations.json; the out-of-station nature is noted here (the
app already has virtual-transfer badges for this).

## Station coordinates (map 1206×1111)

Method: OCR (RapidOCR, 366 texts) + white-dot detection (7 iterations;
best was a top-hat + line-proximity combination) + label-anchored
assignment, then manual verification by 3 subagents split by line group
(Group A: Loop/1/2/5/18/JT/BT; Group B: 3/3B/9/10/15; Group C: 4/6/6B/6C),
then a full numbered-overlay validation (all 282 stations plotted and
viewed in 6 tiles). All 282 coordinates validated on the overlay: every
marker sits on a white dot or interchange disc next to its label.

Key corrections found during verification:
- Fuzzy-OCR duplicate assignments were the dominant error (a station given
  another station's dot): 上新街 was 华新街's dot; 马家岩 was 曾家岩's;
  杨家坪 was 陈家坪's; 天堂堡 was 天堡's; 华岩寺 was 丛岩寺's; 璧山 was
  半山's; 罗家坝/刘家坝 shared 冉家坝's coordinate (388.5,479.0).
- Interchange-icon centres: Group B's "verified" values were sometimes a
  plain line point 8–27px from the true disc (嘉州路 27px, 冉家坝 18px,
  重庆北站南广场 55px). Group C's icon-interior/ring-fit method was more
  reliable for discs. All 10 cross-group conflicts (>4px) were resolved by
  direct crop inspection (see merge notes in the build scripts):
  冉家坝→C (406.4,483.9), 嘉州路→C (521.3,517.1), 头塘→midpoint
  (705.8,457.2), 小龙坎→A (322.5,651.0), 悦来→C (472.7,245.0),
  王家庄→C (472.7,215.1), 红岩村→A (410.1,651.6),
  重庆北站北广场→midpoint (609.0,455.0), 重庆北站南广场→B (600.0,482.0),
  金山寺→C (352.6,348.7).
- 江津高铁 / 圣泉寺 (JT south): Group A mis-assigned them to (110,1047.5)
  and (110,1080.5) — those are the UNOPENED 几江 and 鼎山 dots. A pixel
  scan of the JT vertical line found FOUR white dots (y≈973, 1003, 1047,
  1080) = 江津高铁， 圣泉寺， 几江， 鼎山 in order. Corrected to
  江津高铁 (110,973), 圣泉寺 (110,1003). 几江/鼎山 excluded from data.
- 重庆理工大学 (18号线）: the map draws NO dot for this operating station
  (teal line solid y906–921 between 李家沱大桥 y904 and 花溪工业园 y923,
  verified by pixel scan). Coordinate INTERPOLATED to (503,913) — on the
  line, midway between the neighbours, at the label level. Flagged as
  interpolated; if the user has a better map, re-measure.
- 滩子口 (494,800.5) is provisional (small teal dip, n=4); accepted on the
  overlay but worth a visual check if the map is ever replaced.
- 渝北广场 (814.2,248.7) vs a nearby 3B×10 crossing dot (845.8,247.8):
  Group B chose the plain Line 10 dot under the label; kept.
- 滩子口， 富华路， 鱼洞， 大石坝 were resolved by the owning group (A);
  大石坝 A (410,566) and C incidental (409.8,567.3) agree within 1.5px.

Pinyin/initials in stations.json are from pypinyin (lazy_pinyin).
Spot-checked tricky characters: 蚂蝗梁 mahuangliang, 金鳌山 jinaoshan,
溉澜溪 gailanxi, 渝北广场 yubeiguangchang, 璧山 bishan, 跳磴 tiaodeng,
重庆北站南广场 chongqingbeizhannanguangchang — all correct.

## Fare (VERIFIED — 重庆市发改委 渝发改规范〔2025〕1号, effective 2025-07-30)

Applies to metro lines incl. 15号线 and 国博线， NOT 江跳线/璧铜线.
Distance-based, shortest-path distance when multiple routes exist:
0–4 km ¥2; 4–8 ¥3; 8–12 ¥4; 12–17 ¥5; 17–23 ¥6; 23–30 ¥7; 30–40 ¥8;
40–55 ¥9; 55+ km +¥1 per 20 km. (Pre-2025-07-30 table — 0–6 ¥2 … 63+ ¥10
cap — is SUPERSEDED; several travel guides still show it. Do not use it.)

Cross-checks (both reproduce):
1. 15号线 full length 井口—两江影视城 ≈48 km → 40–55 km bracket → **¥9**.
   Published by the 15号线 opening report (smzdm, 2026-11-12): "本段48公里
   对应单程最高9元". ✓
2. Longest single trip 88 km → 55 km = ¥9, +ceil((88−55)/20)=+¥2 → **¥11**.
   Published as the network maximum. ✓

Discounts (for reference, not fare calculation): 渝通行/渝畅行/重庆畅通卡
9折； monthly spend ¥100+ → 7折， ¥200+ → 5折.

璧铜线 has its OWN fare: 0.4元/人·公里， start ¥2, cap ¥15, added ON TOP
of the metro fare; hours 06:10–21:30 (from 2025-12-31).
江跳线 fare (partially verified, 2025-11-01 notice): start ¥2, cap ¥9
(restored from the 2025-11-01 subsidy removal; before that the max was ¥7
with a ¥2 subsidy). Its exact distance brackets are NOT verified — the
app should show the metro fare for JT trips and note the JT cap, or treat
JT as a separate fare. Do NOT present an unverified JT bracket table.

px/km for the fare model (pixel path length / real line length; the map is
schematic so scale varies — see WIRING.md): Loop 29.76, L1 19.34, L2 22.18,
L3 23.63, L4 20.21, L5 19.60, L6 16.80, L9 26.99, L10 28.90, L15 20.11,
BT 8.97 (far west drawn compressed). Branches share the parent value
(3B→L3, 6B/6C→L6). L18/JT real lengths not confirmed — use ~20 (network
median) and verify when the real length is known. Fare error from scale
variation is typically ±¥1.

## Timetable (web/timetable/cq.json — 282 stations, 345 station-line entries)

Format follows web/timetable/jh.json. At a terminus the toward-self
direction is null (Jinhua convention). Loop dirs are "内环"/"外环".

Sources and status per line:
- Loop (0): last trains REAL from wayschina (last verified 2026-10-04,
  operator schedules via Amap). The official cqmetro.cn static table could
  NOT be re-fetched (site unreachable by curl; Wayback copy is a different
  AJAX page; search did not surface the static table). The wayschina Loop
  columns were verified internally consistent: 外环 is a single train
  departing 二郎 23:00, reaching 华龙 00:25; 内环 is a single train
  departing 重庆图书馆 23:00, reaching 凤鸣山 00:27 via 二郎/华龙/重庆西站/
  上桥 (the apparent discontinuity is just the table listing stations in
  reverse-loop order). Use 工作日 + 全程 (full-route) last train.
  First trains ESTIMATED (anchored 重庆图书馆 06:30 内环 / 二郎 06:30
  外环 + travel-time pattern from the last-train data).
- L1/L2/L3/L4/L5/L6/L9/L10/L18: last trains REAL from wayschina (same
  source/date). Unopened stations EXCLUDED from the transcription
  (顺水寺公园 L4, 南坪 L10, 新桥/邮轮母港 L9 — the wayschina tables list
  them with times; they are not in cq.json). First trains ESTIMATED
  (06:30 terminus departure + real travel-time pattern from the last-train
  data). L4's "To Shunshuisi Park" direction is labelled 石马河立交
  (operating terminus). L9's "To Xinqiao" direction is labelled 高滩岩.
- L3B/6B/6C branch-junction times: the wayschina tables do not list the
  junction station's branch-direction times, so these are DERIVED
  (flagged): 碧津 3B dir=举人坝 last 23:01, dir=鱼洞 last 23:15
  (from 双凤桥 ±2 min); 礼嘉 6B dir=沙河坝 last 22:31, dir=北碚 last
  23:03 (from 欢乐谷 ±2 min); 刘家坪 6C dir=重庆东站 last 22:59,
  dir=北碚 last 23:09 (from 百乐园 ±3 min).
- JT 江跳线: REAL first+last (2026-04-10 timetable). 跳磴 往圣泉寺
  06:30/21:30; 石林寺 06:39/21:34 (往跳磴）, 06:32/21:32 (往圣泉寺）;
  九龙园 06:32/21:27, 06:38/21:38; 双福 06:28/21:23, 06:43/21:43;
  享堂 06:23/21:18, 06:48/21:48; 江津高铁 06:19/21:14, 06:35/21:52;
  圣泉寺 06:15/21:10. Single trip ~28 min. NOTE: 江津高铁 往圣泉寺 first
  train 06:35 is earlier than the through-train pattern (a train from
  江津高铁 at 06:35 would reach 圣泉寺 before the 06:30 departure from
  跳磴 arrives) — likely a depot-originating first train; transcribed as
  published.
- L15: ESTIMATED per-station times (hours 07:30–20:30 verified; ~2 min/stop
  from the 48 km / 18-station layout, 9-min interval). First/last at each
  station = terminus departure ± 2 min × stops. Flagged.
- BT 璧铜线: ESTIMATED per-station times (hours 06:10–21:30 verified;
  ~2 min/stop, 8 stations). Flagged.
- Line hours (verified): most lines 06:30–23:00; 15号线 07:30–20:30;
  璧铜线 06:10–21:30; 江跳线 06:30–21:30 (termini). 5号线北段
  (悦港北路—玉河沟） 07:30–20:30 was reported by one source (gzhphb) but
  wayschina (2026-10-04) shows full 06:30–23:00 service — treat wayschina
  as current, note the discrepancy. L4 往黄岭末班 23:20 reported by 本地宝
  vs wayschina 23:00 terminus departure — trust wayschina.

Wiring must add a `tt.note.cq` key (like `tt.note.hb`/`tt.note.dl`) for the
estimated-timetable note: first trains on most lines are estimated from the
last-train travel pattern; L15/BT per-station times are estimated from
line hours; JT times are real.

## Theme / logo / line colours

- Theme colour: CRT green **#0A814B** (most common logo green; median
  #0F7F4C). Logo is the green CRT mark, cropped from the map top-left
  (x 37–185, y 15–63). Saved as `logo.b64` (PNG). Do NOT redraw.
- Line colours sampled from the map legend swatches (bottom-right legend,
  detected as solid rectangles) except JT/BT, sampled directly from the
  lines: 环线 #E0B754, 1 #D7293C, 2 #1B6E40, 3 #1A49A5, 4 #CD8142,
  5 #38A2D2, 6 #E68099, 国博 #EA9DB2, 9 #862843, 10 #4B267A,
  15 #2565A7, 18 #65CDC4, JT #1E5CA9, BT #1C589A. Branch lines share
  parent colour (3B=#1A49A5, 6B=#EA9DB2, 6C=#E68099).

## Transit app

**渝畅行 (Yuchangxing)** — official Chongqing Rail Transit app (乘车码，
首末班车/快车时刻表查询； supports UnionPay/WeChat/Alipay). App Store id
**1491110313**, seller Chongqing Rail Transit (Group) Co., Ltd., bundle
com.bwton.msx.ycx (via iTunes Search API, 2026-11-17). 渝通行 is the BUS
app — do not confuse them. No confirmed URL scheme → App Store link.

## Splash

Real splash image sent by the user (white bg, calligraphy 重庆， circular
track-layout diagram with a green line, small green dash, "CHONGQING
SUBWAY · TRACK LAYOUT LOOKUP"). Saved as `splash-user.jpg` (edited) and
`splash-user-orig.jpg` (unedited original); `splash.b64` encodes the EDITED
version. Edit (per the user's instruction to remove 配线查询 from ALL
splash images including its English translation): removed "· TRACK LAYOUT
LOOKUP" (kept "CHONGQING SUBWAY") by filling x 372–800, y 1598–1628 with
the local background RGB(254,254,254). Visually verified: no text remnant,
no smudge, calligraphy/diagram/green dash intact. NOTE: the user asked for
this removal on ALL cities' splash images — only Chongqing has been done
so far; Harbin, Dalian, Jinhua, etc. are still owed.

## Files

- `web/chongqing/stations.json` — 282 stations {n, py, ini, x, y}
- `web/chongqing/routes.json` — 16 line keys, 330 edges (Loop closed ring)
- `web/chongqing/map.svg` — JPEG-in-SVG, id="svg8", base64 payload verified
  byte-identical to the user's source image
- `web/chongqing/logo.b64` — CRT logo PNG (cropped from map)
- `web/chongqing/splash.b64` — edited real splash (see above)
- `web/chongqing/splash-user.jpg` / `splash-user-orig.jpg` — edited /
  unedited splash images
- `web/timetable/cq.json` — 282 stations, 345 station-line entries
- `web/chongqing/NOTES.md` (this file), `web/chongqing/WIRING.md`
- Working files (in /tmp, NOT deliverables): cq_tt_data.py,
  cq_tt_build.py, cq_merged.json, cq_overlay_2x.png, cq_group_A/B/C_result.json
  (backed up as `_group_*_result.json` in this dir — remove at the end),
  `_lines.json`, `_op.json` (working copies — remove at the end)

## Open questions

1. 江跳线 exact distance-based fare brackets — only start ¥2 / cap ¥9
   verified (2025-11-01 notice). Do not present an unverified bracket table.
2. L18 / JT real line lengths (for px/km) — not confirmed; WIRING.md uses
   ~20 px/km (network median) as a placeholder.
3. 重庆理工大学 coordinate is interpolated (map omits its dot) — re-measure
   if a better map is available.
4. 滩子口 (494,800.5) is provisional (small teal dip) — accepted on the
   overlay; re-check if the map is replaced.
5. Loop timetable: wayschina last trains used (internally consistent);
   the official cqmetro.cn static table could not be re-fetched. If the
   official table is obtained later, diff it against cq.json.
6. 5号线北段 hours discrepancy (gzhphb 07:30–20:30 vs wayschina full
   06:30–23:00) — wayschina treated as current.
7. JT 江津高铁 06:35 first-train anomaly (see timetable section).
8. No lat/lng for any city yet — location + nearby stations shows
   "即将上线" for all cities. Never fabricate coordinates.
