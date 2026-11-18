# Shenzhen （深圳） — wiring spec for template.html + build_offline.py

City key: `sz`. Name: 深圳 / 深圳 / Shenzhen. Status: **data package complete EXCEPT `map.svg`, logo and splash** (see blockers below). Do NOT edit `template.html` or `build_offline.py` from this spec alone — this is the checklist for the template agent that does the wiring.

## Data files (all verified, cross-checked)

| File | Content | Verified |
|---|---|---|
| `web/shenzhen/network.json` | Canonical spec: 17 lines, 351 unique stations, 433 line-entries, 69 interchanges, fare rule, transit app, theme, 20 unopened (excluded) | Phase 1 |
| `web/shenzhen/NETWORK.md` | Human-readable spec + 38 sources + notes (2/8 through-running, out-of-station pairs, distinct pairs) | Phase 1 |
| `web/shenzhen/stations.json` | 351 unique stations `{n, py, ini, x, y}`; x,y are RMP node coordinates verbatim | Map agent, 351/351 matched |
| `web/shenzhen/routes.json` | 17 lines `{color, name, stations}` + 416 edges (adjacent pairs, line order); 433 line-entries | Map agent, 416/416 adjacency walk |
| `web/timetable/sz.json` | Per-station first/last, 351 stations, 17 lines, 832 timed + 34 null self-directions; **zero ESTIMATED lines** | Timetable agent |
| `web/latlng/latlng-sz.json` | 351/351 coordinates (Wikidata SPARQL 315 + API/OpenCC 33 + zh Wikipedia 2 + Nominatim 1) | Lat/lng agent, 100% |
| `web/shenzhen/build_sz.py` | Reproducible builder + verifier (re-run prints `ALL CHECKS PASS`) | Map agent |
| `web/shenzhen/rmp-gallery-shenzhen.json` | RMP Gallery source (791 nodes, 634 edges, v76) | Map agent |
| `web/shenzhen/MAP_EXPORT.md` | The one remaining browser step for `map.svg` (see blocker 1) | Map agent |

Cross-file check (coordinator, 2026-11-19): stations == routes == timetable == latlng == network name sets (351 each); line-entries 433; edges 416 = 433 − 17; every station has x,y,py,ini; every timetable line-set matches network.json; no unopened station/line anywhere (福邻, 西丽高铁站, 歌剧院, 潮汐公园 absent).

## Facts for wiring

- **Lines (17):** 1 (30), 2 (32), 3 (38), 4 (23), 5 (37), 6 (27), 6B (7), 7 (29), 8 (12 incl. shared 莲塘; official count 11), 9 (32), 10 (24), 11 (22), 12 (39), 13 (26), 14 (18), 16 (32), 20 (5). Colours are in `network.json` / `routes.json` (hex, no `#`). 2/8 through-run via shared 莲塘.
- **Theme colour:** `00A051` (Shenzhen Metro system colour). Line 1 green `00AB39` is the close alternative — use `00A051` for the city theme.
- **Fare (verified, official 票制票价 via Bendibao):** ordinary class, shortest-path: first 4 km ¥2; 4–12 km +¥1 per 4 km; 12–24 km +¥1 per 6 km; beyond 24 km +¥1 per 8 km; network cap ¥2–¥14 (longest 双龙—碧头 89.7 km = ¥14). Line 11 business class: ordinary + 2× the Line 11 portion, ≤3× ordinary, ¥6–¥35. One-day ¥25, three-day ¥75. **Fare is an ESTIMATE in-app** (same as other cities).
- **Transit app:** 深圳地铁-官方APP, App Store id `848926994` (seller Shenzhen Metro Group Co., Ltd., bundleId com.sz.metro). **URL scheme: none verified — do NOT invent one; link to the App Store.**
- **Logo:** official Shenzhen Metro logo exists on Wikimedia Commons (via the Shenzhen Metro article) — recorded only, NOT fetched/redrawn. No `logo.b64` delivered.
- **Splash:** no Shenzhen splash image delivered. The user supplies real splash photos; do NOT generate one. (Blocker 3 below.)
- **Timetable notes:** weekday times only (same convention as other cities). 165 last-train values run past midnight (00:00–00:44) — normal, same as Beijing/Shanghai. First-train times are non-monotonic on some lines (depot-start / short-turn trains) — genuine published values, keep as-is. APEC-week (Nov 16–20, 2026) temporary +1 h service was excluded.
- **Out-of-station transfer pairs** (flagged in NETWORK.md): 湖贝, 福田口岸, 红岭南 are out-of-station pairs. No `SZ_TRANSFERS` seed is delivered and no walking distances were verified — wire `window.SZ_TRANSFERS = {}` (empty) for now; wiring these as virtual transfers needs the counterpart station name + a verified walking distance (follow-up, do not guess).
- **Distinct pairs (do not merge):** 老街 vs 东门 (157 m apart), 大剧院 vs 红岭南 (349 m apart).
- **Briefing/upcoming already reference `sz`:** `sz13` (深圳13号线南延, colour DE7C00, 2027) is in the upcoming list and the briefing city map (`sz13 → 'sz'`). Once Shenzhen is supported, the per-city briefing filter will show it for Shenzhen. Keep it as "upcoming" — it is the unopened south extension, NOT in the operating network.

## Blockers (must be resolved before / during wiring)

1. **`map.svg` is NOT delivered.** RMP Gallery serves only the project JSON + a PNG thumbnail; there is no direct SVG download. One browser step is required — exact steps in `web/shenzhen/MAP_EXPORT.md`: open `https://railmapgen.org/?app=rmp&searchParams=shenzhen` → Download → SVG v2 → save as `web/shenzhen/map.svg` → rename root id `canvas` → `svg8` → delete the `<g id="rmp_info">` credit element (`https://railmapgen.org/?app=rmp`, x=60, y=25). Coordinates will match by construction (stations.json x,y are the RMP node coordinates verbatim). The build_offline.py Shenzhen step must not fail hard if `map.svg` is still missing — do the browser export first, or make the step tolerant.
2. **No `logo.b64` / `splash.b64`.** Fetch the official logo from Wikimedia Commons (do not redraw/alter it) or leave the logo empty/fallback; the splash needs a user-supplied photo (or a neutral placeholder only if the parent approves). Do not generate either.
3. **Fare px/km calibration is NOT done.** `routeFare` uses km from `segKm` (map units → km). Beijing uses 44 units/km; Shanghai uses a two-zone model. Shenzhen's RMP coordinates have NO calibrated px/km scale yet. The template agent must derive it from real line lengths (e.g. the published length of Line 11 / the 双龙—碧头 89.7 km longest trip) and add a Shenzhen branch to `segKm` — do NOT guess the scale, or fares will be wrong.

## Wiring checklist (template.html)

Follow the Changzhou (`cz`) pattern exactly (same markers, same field names, same branch structure). Line numbers below are approximate (template.html moves); search by the anchor text.

1. **i18n:** add `'city.sz': ['深圳', '深圳', 'Shenzhen']` after `'city.cc'` (~1730).
2. **Seed markers (top of file, with the other `window.*` seeds):** add `window.SZ_STATIONS = /*__SZ_STATIONS__*/[];`, `window.SZ_ROUTES = /*__SZ_ROUTES__*/null;`, `window.SZ_MAP = /*__SZ_MAP__*/"";`, `window.SZ_TIMETABLE = /*__SZ_TIMETABLE__*/{};`, `window.SZ_LATLNG = /*__SZ_LATLNG__*/{};`, `window.SZ_LOGO = /*__SZ_LOGO__*/'';`, `window.SZ_SPLASH = /*__SZ_SPLASH__*/'';`, `window.SZ_TRANSFERS = /*__SZ_TRANSFERS__*/{};` (empty for now — see out-of-station note above).
3. **data() fields:** add `szStations: (window.SZ_STATIONS || []), szRoutes: (window.SZ_ROUTES || null), szLogo: (window.SZ_LOGO || ''), szMap: (window.SZ_MAP || ''), szSplash: (window.SZ_SPLASH || ''), szTimetable: (window.SZ_TIMETABLE || {}), szLatLng: (window.SZ_LATLNG || {})` alongside the `cz*` fields (~1977–1984).
4. **Valid-city restore (~1915):** add `'sz'` to the localStorage city check.
5. **cityList() (~3871):** add `{ key: 'sz', name: this.t('city.sz') }` (append after `'cc'`). **Remove `'深圳'` from `soonCityList()` (~3879)** — it is now supported (49 → 48 upcoming).
6. **switchCity:** add guard `if (c === 'sz' && (!this.szStations.length || !this.szMap)) return;` with the other guards (~2310), and a branch `else if (c === 'sz')` setting `stations/routes/transfers/curr` (transfers = `window.SZ_TRANSFERS || {}`, `curr = { svgUrl: "", svgDom: this.szMap, pdfUrl: "", success: true, json: null, verName: "SZ", verInfo: "{ " + this.t('map.verInfo', {c: this.t('city.sz'), d: '2026-11', l: 17, s: 351}) + " }", ... }`) following the `cz` branch (~2368).
7. **Theme:** add `'sz-theme'` to the `#app :class` binding (~1006), to the `themes` array and `tc` map in `syncHtmlClasses()` (~2690–2692), and add a `.sz-theme` CSS block (theme colour `00A051`) following the other cities' `.xx-theme` rules (`.tr-search`, `.tr-pref button.on`, `.sp-row .sp-line`, `.tr-swap`, `.tr-tabs button.on`).
8. **cityLogo() (~3881) and cityLogoFor(k) (~3336):** add `'sz' → this.szLogo`.
9. **splashImg():** add `'sz' → this.szSplash` (same ternary chain as the other cities).
10. **latLngFor(c) (~3236):** add `if (c === 'sz') return this.szLatLng;`.
11. **Fare (`routeFare`, ~2874):** add a Shenzhen branch with `fareForKmSz(km)`: km ≤ 4 → 2; 4 < km ≤ 12 → 2 + ceil((km−4)/4); 12 < km ≤ 24 → 4 + ceil((km−12)/6); km > 24 → 6 + ceil((km−24)/8); cap at 14. (Check the arithmetic against the verified rule: 12 km → ¥4, 24 km → ¥6, 40 km → ¥8, 89.7 km → ¥14.) Requires the `segKm` px/km calibration from blocker 3 first. Line 11 business class is NOT modelled (ordinary fare only, same as other cities' estimates).
12. **Search-button / accent colour:** Shenzhen's search-button colour follows the theme (`00A051`) unless the template agent finds a different per-city accent in the existing pattern — use the theme colour.

## Wiring checklist (build_offline.py)

Add a Shenzhen step following the Changzhou step (S2, ~274–290): read `web/shenzhen/stations.json`, `routes.json`, `map.svg`, `logo.b64`, `splash.b64`, `web/timetable/sz.json`, `web/latlng/latlng-sz.json` and substitute into the `/*__SZ_*__*/` markers with `sub_once` (same assertions: no `</script` in the JSON). **Do not fail the whole build if `map.svg`, `logo.b64` or `splash.b64` are missing** (blockers 1–2) — either complete those first or make the step skip the missing asset with a clear warning. Never push `web/offline/index.html` (CI rebuilds it).

## Out of scope (not in this package)

- **Trains (`trains.json`):** Shenzhen train models are NOT included (the file covers the 9 existing cities only). The train search （车型检索） will not return Shenzhen trains until that data is added — separate task.
- **Virtual transfers:** `SZ_TRANSFERS` is empty (see above). The out-of-station pairs need verified distances first.
- **Logo/splash assets:** not delivered (blocker 2).
- **`map.svg`:** not delivered (blocker 1 — one browser export step).

## Verification for the wiring agent

After wiring, run the standard checks: `node --check` on the extracted inline scripts + a jsdom mount test (serve the fresh offline build over HTTP; `#app` children > 0, no real console errors). Confirm: Shenzhen appears in the city picker, switching to it loads the map + 351 stations, a route can be planned, the fare shows a Shenzhen-rule estimate, the timetable shows per-station first/last, and nearby stations work. The map itself needs an on-device visual check after the browser export.
