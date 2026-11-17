# 虚拟换乘 (Virtual Transfers) — NOTES

Per-city virtual-transfer data for the Subway motion app. Format matches
Beijing's `web/transfers.json` (hand-maintained, Wikipedia 转乘站）:

- SAME-NAME, routable (badge only): `{"站名": {"lines": ["1","16"], "dist": "约700米", "note": "虚拟换乘，需出站步行"}}`
  The station name is shared by two lines but the two line-stations are
  physically separate, so riders must exit and walk. The router treats
  same-name stations as ONE node, so these ARE routable; the entry only
  makes the badge show.
- SAME-NAME, only SOME pairs virtual: add `"pairs": [["3","14"],["4","14"]]`
  (build 66). The badge shows only for those pairs — the plain "lines"
  list would also badge in-station pairs (e.g. 曹杨路 3↔4) at the same
  station name. When "pairs" is present it takes precedence over "lines".
- DIFFERENT-NAME, non-routable (documented only): `{"复兴门": {"lines": ["1","2"], "other": "太平桥", "otherLines": ["19"], "dist": "约500米", "note": "虚拟换乘，需出站步行", "routable": false}}`
  Two different station names, no edge between them, NOT routable.

Wiring: `web/build_offline.py` section L2 inlines each per-city file as
`window.SY_TRANSFERS` / `SH` / `HB` / `DL` / `JH` / `CZ`; `web/template.html`
`switchCity()` assigns `this.transfers` per city (Beijing keeps
`window.METRO_TRANSFERS`). `virtualInfoFor` (template.html) shows the badge
"虚拟换乘 · 出站步行{dist}" at a route segment boundary when the entry's
lines/pairs include both the previous and current segment lines.
Verification harness: `/tmp/vt-test.js` (node).

## Beijing (existing, untouched)
4 entries: 木樨地 1/16 约700米； 大钟寺 12/13 约300米；
复兴门 1/2 ↔ 太平桥 19 约500米 (routable:false);
广安门内 7 ↔ 牛街 19 约400米 (routable:false).

## Shanghai — 5 verified virtual-transfer stations (official list)
Sources: Shanghai Metro fare guide (上海轨道交通虚拟换乘车站）,
Wikipedia 转乘站. The official list is exactly 5 — a "six" figure in one
travel guide is stale: the old 6th was 娄山关路 (2↔15), virtual
2021-01-23–2024-12-31, now in-station (new passage opened 2026-03-22).
Entries use "pairs" (only the listed pairs are virtual; the other pairs
at the same station name are in-station). "lines" lists all lines at the
station (documentation); "pairs" governs the badge.

- 上海火车站: pairs 1↔3, 1↔4 (L3/L4 share one ground island platform,
  in-station; L1 separate). dist 约500米 — ESTIMATE, no published number:
  en Wikipedia 8-min walk × ~60 m/min effective speed (incl. stairs);
  南广场↔北广场 straight line is only ~176m (Moovit) but the real route
  uses the underground passage between the squares.
- 南京西路: pairs 2↔12, 2↔13, 12↔13 (ALL three pairs virtual — CORRECTION
  to the first assumption: Wikipedia 南京西路站: "2号线-12号线-13号线均为
  出站换乘"; the ⊥-shaped underground passage was never built because of
  the 张园 redevelopment, three separate station bodies with independent
  entrances). dist 约400米 — ESTIMATE: 上海本地宝 2015 "12、13号线站换
  2号线步行需5分钟左右"; per-pair ~300m (2↔13), ~350m (12↔13), ~450m (2↔12).
- 曹杨路: pairs 3↔14, 4↔14, 11↔14 (L3/L4 same platform; L3/L4↔L11 in-station
  passage; L14 separate). dist 约700米 — SOURCED (Sina/新民晚报 2021-12-30
  field test): ground distance between exits ~500m, ~700m including the
  walk from exits to ticket gates; 11号线 5号口↔14号线 12号口 500m.
- 长清路: pairs 7↔13. dist 约200米 — ESTIMATE: the unbuilt transfer
  passage is 90.85m long (Sina 2021-03-02, citing 申通建设）; the current
  route (13号线 6号口 exit → cross the street → 7号线 2号口) is ~2× that.
- 虹桥2号航站楼: pairs 2↔10. dist 约200米 — ESTIMATE: no published
  inter-hall figure; comparable in-hub walk (虹桥火车站 exit → T2 metro
  entrance) is "步行约200米" (上观/新浪 2026-09-30 guide). DIRECTION RULE:
  toward downtown is SAME-PLATFORM in-station (2号线往浦东1号2号航站楼 ↔
  10号线往基隆路/航中路， 30.8m island platform since 2017-12-30); ALL other
  direction combinations require exiting (three halls not connected). The
  router has no direction at a segment boundary, so the badge shows for
  every 2↔10 transfer here and the note carries the exception:
  "往市区方向可站内同台换乘". (Workaround "穿车厢" through a train is not
  an official transfer — not modelled.)
General rule (for help text, not in the data): 交通卡 / Metro大都会,
30分钟内出站再进站连续计费；单程票不支持虚拟换乘，需重新购票.
File: `web/shanghai/transfers.json` (5 entries).

## Shenyang — ZERO verified
All 15 multi-line stations confirmed in-station (Wikipedia 沈阳地铁
1/2/3/9/10号线 articles + 沈阳北站站 article): 青年大街 1/2 十字交叉型节点；
铁西广场 1/9 通道/垂直； 滂江街 1/10 站厅长通道； 太原街 1/4 站厅长通道；
中医药大学 10/2 站厅长通道； 沈阳北站 2/4 站厅通道（两线站厅层在付费区内连接）；
工业展览馆 2/3 长通道； 奥体中心 2/9 站厅通道； 大通湖街 3/9 站厅；
砂阳 3/4 通道； 江东街 10/3 长通道； 合作街 10/4 站厅通道；
淮河街沈医二院 10/9 垂直/站厅通道； 长青南街 10/9 垂直/站厅通道；
长白南 4/9 垂直/站厅通道.
Different-name candidates from map proximity (36 pairs, e.g. 启工街↔兴华公园
~240m, 北塔↔洮昌街 ~250m, 方型广场↔青年公园 ~280m): NONE documented as a
virtual/out-of-station transfer — not added. (Metro↔tram transfers, e.g.
奥体中心 to 浑南有轨电车， require exiting + re-paying, but that is
metro↔tram, not metro↔metro — out of scope.)
File: `web/shenyang/transfers.json` = `{}`.

## Harbin — ZERO verified
All 5 multi-line stations confirmed in-station (official count is exactly
5 换乘车站， 哈尔滨文明网 2024-11-27): 太平桥 1/3 节点换乘、大厅换乘；
人民广场 2/3 T型节点换乘 + 站厅换乘； 医大二院 1/3 十字节点换乘 + 站厅换乘
(哈尔滨地铁首个换乘站）; 博物馆 1/2 in-station (field report + official list);
珠江路 2/3 listed as 换乘站 (network-wide "不用出站" statement; individual
transfer-mode wording not found in a dedicated source).
Different-name candidate 大有坊街(3)↔交通学院(1) ~690m: not documented;
both are one stop from 太平桥 (the L1↔L3 interchange), so a virtual pair
there would be redundant — not added.
File: `web/harbin/transfers.json` = `{}`.

## Dalian — ZERO verified
All 8 accounted for: 后盐 3/5 通道换乘； 大连站 3/5 通道换乘
("不用，是站内换乘，无需出站", 大连本地宝）; 青泥洼桥 2/5 157m 通道换乘
("换乘无需出站"); 大连北站 1/2 地下二层双岛平行换乘； 西安路 1/2
地下三层双岛重叠平行换乘； 河口 1/12 双岛四线平行换乘；
九里 13/3B NOT a transfer — 13号线与3号线支线贯通运营，无需下车换乘；
开发区 3/3B same-line branch junction, not a transfer.
No different-name candidates within ~1000m; no documented virtual transfer.
(Note: one Sina guide wrongly lists 大连北站 as 1/13号线换乘 — 13号线二期
to 大连北站 is planned, not operating; the operating pair is 1/2.)
File: `web/dalian/transfers.json` = `{}`.

## Jinhua — ZERO verified
秦塘 (JY/YD): 双岛四线同站台换乘 (金华本地宝） — in-station,
same-platform. Only multi-line station; no different-name candidates.
File: `web/jinhua/transfers.json` = `{}`.

## Changzhou — ZERO verified
文化宫 (1/2): T型节点换乘 + 站厅换乘 (Wikipedia station article) —
常州地铁唯一的换乘站. No different-name candidates.
File: `web/changzhou/transfers.json` = `{}`.

## Chongqing — RESEARCH DONE, NOT WIRED (pending data stability)
Chongqing data prep is still in progress by another agent (agent 53eba99f,
still running 2026-11-18 00:45); its stations.json/routes.json may still
change, so no `web/chongqing/transfers.json` was written and nothing was
added to build_offline.py/template.html for CQ. Research (2026-11-18,
Wikipedia 转乘站 + per-station articles): **4 stations, 6 line pairs**.
Ready-to-wire draft (Beijing format; 环线 key is `"0"`):

```json
{
 "玉带山": {"lines": ["0", "4"], "dist": "约200米", "note": "虚拟换乘，需出站步行"},
 "歇台子": {"lines": ["1", "5", "18"], "dist": "约200米", "note": "虚拟换乘，需出站步行"},
 "观音桥": {"lines": ["3", "9"], "dist": "约50米", "note": "虚拟换乘，需出站步行"},
 "杨家坪": {"lines": ["2", "18"], "dist": "约300米", "note": "虚拟换乘，需出站步行"}
}
```

- 歇台子 1/5/18: ALL THREE pairs virtual — "由于三线站台间换乘通道尚未
  开通，1号线、5号线与18号线之间换乘需要出站" (Wikipedia 歇台子站）;
  dist 约200米 (重庆日报 2020-06-23: "每两条线间换乘距离约200多米").
  Note: if the wiring ever needs pairwise entries, split into 1/5, 1/18,
  5/18 (same distance). With the current "lines" format the badge shows
  for any pair, which is correct here since all three pairs are virtual.
- 玉带山 环线↔4: 出闸换乘 ("环线3号出口与4号线7号出口在地下连通");
  4号线西延段 opened 2026-02-10 already as out-of-station transfer.
  dist 约200米 — ESTIMATE, no published number (4号线站体长 242.2m).
  ⚠️ EXPIRY RISK: the in-station passage is "预计于2026年内完工"
  (Wikipedia, updated ~8 days before this note) — re-check before wiring;
  it may become in-station at any time in late 2026.
- 观音桥 3↔9: dist 约50米 — SOURCED (上游新闻 2022-01-25 field visit:
  "只需步行四五十米，即可到达3号线的进出站口"); a 2026-10-19 9号线 guide
  still calls it 出站换乘.
- 杨家坪 2↔18: dist 约300米 — SOURCED (18号线 opening report 2023-12-28:
  "18号线5号出入口往杨家坪正街方向步行300米" to 2号线 2号口； alternative
  via 高进支路 ~250m); Wikipedia: "在可预见的将来会维持出站换乘".
- EXCLUDED (verified in-station, not virtual): 璧山 1↔BT — 站厅换乘
  (the "虚拟换乘：仅限宜居畅通卡" line in the 1号线 route template is a
  map legend, not a station note); 跳磴 5/18/JT — 同台换乘 (5↔江跳线）
  + 站内通道 (5↔18, 18↔江跳线）; 跳磴南 (18) ↔ 圣泉寺 (JT) are ~26 km
  apart (different districts), not a walk — the template text was a
  legend/branch layout overlap; 沙坪坝 — in-station since the interchange
  hall opened 2022-09-30 (ignore a 2026-10-19 guide still calling it
  出站换乘 — outdated); 重庆西站 5/环线同站台； 重庆北站南广场 环/3/10;
  重庆北站北广场 4/10; 两路口 1/3; 曾家岩 2/10; 红岩村 5/9; 富华路 9/18.
- Different-name nearby pairs with EXPLICITLY NO virtual transfer
  (Wikipedia: "不设置虚拟换乘", fares are separate — do NOT add):
  园博园(3)↔园博中心(5), 回兴(3)↔兴科大道(9), 狮子坪(3)↔龙头寺公园(10).
- 15号线 status: OPERATING — 井口至两江影视城段 opened 2026-11-12
  14:00 (重庆市政府网/重庆日报 2026-11-13; 华龙网 2026-11-12), 18 stations,
  matching app routes.json station-for-station (二期曾家–井口段 not open,
  correctly absent). Hours 7:30–20:30, min headway 9 min — timetables
  must use this, not the usual 6:30–23:00.
- ⚠️ DATA FLAG for the Chongqing data agent (not fixed here — another
  agent owns Chongqing data): app 5号线 contains 玉河沟站， but 本地宝
  5号线 page says "玉河沟站暂缓开通" — it should be removed from operating
  data per the user's standing rule (unopened stations never in searchable
  data). 9号线 29 stations verified correct (31 − 未开通新桥/邮轮母港）;
  4号线 correctly excludes 未开通顺水寺公园站.

## Changchun — SKIPPED (no data yet)
stations.json does not exist yet (data prep unfinished). No transfers file.
Wire when Changchun data prep completes.

## px/km scales used (different-name candidate search)
Shanghai ~25 (new 1206×691 schematic; per-line 6.4–32.0, median 23.6);
Shenyang ~34 (new 1166×826 geographic; per-line 26.2–45.4, median 34.2);
Harbin ~45 (NOTES: overall 45.82); Dalian ~25 central (per-line 8.3–27.2,
suburban lines compressed); Chongqing ~24 (median 23.9);
Jinhua JY 11.90 / YD ~13.06 (NOTES); Changzhou L1 38.12 / L2 42.22 (NOTES).
Threshold ~800–1000m. Pixel proximity on schematic maps is unreliable
(most candidates are just nearby parallel-line stations) — only
DOCUMENTED virtual transfers were included.
