# Beijing — two map types (build 78)

Beijing now has TWO maps, chosen from Settings > Switch City (three-level
menu: Settings > Switch City > Beijing > 配线图 / 线路图).

## The two maps

| Type | File | Source | Stations |
|---|---|---|---|
| 配线图 (track layout, DEFAULT) | inlined `MTR2.8.0.svg` via `#svgData` (SierraQin/metro v2.8.0, CC0) | `web/vendor/MTR2.8.0.svg`, loaded by `loadProd()` into `env.prod` | `web/stations.json` (418, 配线图 coords) |
| 线路图 (schematic line diagram) | `web/beijing/map-line.svg` (1,470,290 bytes, viewBox `-836.5 -599 1664.5 1127.23`, root id `svg8`) | railmapgen.org RMP Gallery Beijing work (`public/resources/real_world/beijing.json`, 807,794 bytes, last update ~2026-06-30), rendered with the RMP app's own export (`svg-wrapper-export-bj.test.tsx` in `~/workspace/cd-scout-tmp/rmp`, vitest+jsdom, `makeRenderReadySVGElement`) | `web/beijing/stations-line.json` (417, RMP graph coords) |

- Map-type state: `bjMapType` (`'track'` default / `'line'`), persisted in
  localStorage `metro-bj-maptype`. `switchCity('bj')` picks map+stations by
  `bjMapType`; `pickBjMapType(t)` sets it and re-applies (force switch when
  already on Beijing).
- RMP graph coords map 1:1 onto the exported SVG (`<g transform=
  "translate(x, y)">`, dot at group origin) — verified for a basic station
  (天安门西 -20,0) and an interchange (天通苑 85,-415). `stations-line.json`
  x,y are the RMP graph coords directly.
- RMP credit text was at (60,25)/(60,50) — inside the dense map centre, over
  lines — so it was moved to the blank bottom-left corner (-820,500)/(-820,525).
  Verified blank: westernmost node x=-786.5 is at y=292, southernmost node
  y=470 is at x=0; nothing is near (-820..-540, 468..525).
- `build_offline.py` inlines the new files via `/*__BJ_LINE_MAP__*/` and
  `/*__BJ_LINE_STATIONS__*/` (same pattern as the other cities).

## Station coverage — read before "fixing" a missing station

- `stations-line.json` = the SAME 418 operating stations as `stations.json`,
  with RMP coordinates, MINUS 红庙 (417). 红庙 is in `stations.json` but is
  NOT in the RMP map and is in NO route — a pre-existing quirk; it is not
  searchable on the 线路图.
- Line 18's 3 stations are DRAWN on the 线路图 but NOT searchable/routable
  there (and not on the 配线图 either): 上地软件园 / 东北旺 / 龙泽西.
  - The RMP map HAS all three with coordinates (上地软件园 -247.5,-375;
    东北旺 -195,-375; 龙泽西 -135,-405).
  - They are NOT in `stations-line.json` because they are NOT in the shared
    `routes.json` Line 18 route (which has only 8 stations). Adding them to
    search without route edges would make them searchable-but-unroutable.
    龙泽西 IS in `stations.json` (配线图 coords 1600,1594) so it IS in
    `stations-line.json` and searchable, but still not in the L18 route.
  - Fixing this properly (add all 3 to `routes.json` L18 + timetable +
    `stations.json` with 配线图 coords) is the separate open item #1.
- Other stations DRAWN on the RMP 线路图 but NOT searchable (not in
  `routes.json`): 上岸 (S1, operating — the known "S1 missing 上岸" gap),
  八角游乐园 (Line 1), 模式口 (Line 1), 万安, 九号村. These need route +
  timetable work before they can join search; do NOT add them to
  `stations-line.json` alone.
- Unopened, correctly EXCLUDED from search (drawn but `open: false` in RMP):
  陶然桥 (Line 14), 老观里. Per the user rule, unopened stations never
  enter search.
- The RMP map's station count (426 nodes, 424 open) vs the app's 418 is
  explained by the above: the 9 RMP-only names are the 3 Line 18 + 上岸 +
  八角游乐园 + 模式口 + 万安 + 九号村 + the 2 unopened (陶然桥/老观里),
  minus 红庙 which is app-only.
