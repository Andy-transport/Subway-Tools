# Wiring Chengdu (`cd`) into the app

This file lists the exact edits to wire the prepared Chengdu data
(`web/chengdu/`, `web/timetable/cd.json`, `web/latlng/latlng-cd.json`)
into the app as city `'cd'` (the 10th city). It follows the Changchun
(build 66) / Chongqing pattern exactly. Anchor on the `cc` blocks, not
on line numbers — line numbers WILL shift.

## Files already prepared (do not re-create)

- `web/chengdu/stations.json` — 364 operating stations {n, py, ini, x, y}, sorted by pinyin. Match rate 364/364 against map.svg; no coordinate guessed.
- `web/chengdu/routes.json` — 17 lines (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 17, 18, 19, 27, 30, S3), 449 line-stations, 433 edges, `lines` + `edges` (Changchun format). Line 1 branch is a single ordered list with the branch inserted after the junction (Beijing T1 precedent): […, 四河, 广都, 五根松, 华阳, …, 科学城] (35 stations); edges use the main chain (四河–华阳) plus spur edges 四河–广都 and 广都–五根松.
- `web/chengdu/map.svg` — RMP Gallery Chengdu vector SVG (railmapgen/rmp-gallery, chengdu.json, RMP v69, last gallery update 2026-06-08), rendered with the project's own code; root id `svg8`, viewBox `-872.5 -747.5 1903 1555`, 1903×1555. One cosmetic artwork gap: Line 30 玉石–惠王陵 has no drawn segment (both dots exist and are correct; routing does not use SVG geometry).
- `web/timetable/cd.json` — first/last times, all 364 stations. **The whole file is ESTIMATED** (derived from official terminus times at 2.0 min/interval — see "Timetable" in NOTES.md). Must be checked against the official Chengdu Metro timetable before shipping.
- `web/latlng/latlng-cd.json` — 362/364 stations (99.5%). Missing: 净居寺 (no Wikidata item) and 龙泉驿火车站 (Wikidata item exists but has no coordinate yet). No coordinates guessed.
- `web/chengdu/research.json` — full research data (lines, colours, fare, timetable sources, not-yet-open list, transit app, theme, logo URL).
- `web/chengdu/NOTES.md` — full data documentation (research traps, timetable method, builder notes).

**Not yet prepared (must be obtained before wiring):**
- `web/chengdu/logo.b64` — the official Chengdu Metro logo. A clean public-domain SVG exists on Wikimedia Commons (`Chengdu Rail Transit icon.svg`, 476×127): https://upload.wikimedia.org/wikipedia/commons/b/bc/Chengdu_Rail_Transit_icon.svg — **NOT downloaded**: Wikimedia's upload server returned an error/HTTP 429 to this VM (tried both the direct upload URL and Special:FilePath). Download it from a network where Wikimedia is reachable, base64 it to `logo.b64`, and do NOT redraw or alter it.
- `web/chengdu/splash.b64` — **a real user splash photo is needed** (the user supplies real splash photos for each city). Do NOT generate one. Until the user supplies it, wiring cannot complete the native splash (build.sh) — the web splash will fall back to the Beijing splash; note this as a known gap.
- `web/cdmetro-icon.b64` — the 成都地铁-官方APP icon for the transit-app jump row. Not yet sourced. If it cannot be sourced before wiring, reuse `logo.b64` as the fallback (same as Changchun, where the transit icon and logo were identical bytes) and note it.

**Not yet prepared (later, optional):**
- `web/chengdu/transfers.json` (virtual different-name transfers). Same-name interchanges route normally; different-name virtual transfers are not available for `cd` until this is built. Follow the `cq` pattern (`build_offline.py`, `template.html` `window.CC_TRANSFERS` equivalent).

## 1. `web/template.html`

### 1a. Global placeholders (after the CC ones)
```js
window.CD_STATIONS = /*__CD_STATIONS__*/[];
window.CD_ROUTES = /*__CD_ROUTES__*/null;
window.CD_MAP = /*__CD_MAP__*/"";
window.CD_LOGO = "data:image/png;base64,/*__CD_LOGO__*/";
window.CDM_ICON = "data:image/png;base64,/*__CDM_ICON__*/";
window.CD_SPLASH = "data:image/png;base64,/*__CD_SPLASH__*/";
window.CD_TIMETABLE = /*__CD_TIMETABLE__*/{};
```

### 1b. Root div theme class
Add `'cd-theme': city === 'cd'` to the `:class` binding (after `'cc-theme'`).

### 1c. CSS — add after the `.cc-theme` rules
```css
/* Chengdu theme: Line 1 #0F0F96 (official line colour, Chengdu
   DB510100/T 083-2012 wayfinding standard; no single official system
   brand colour is published). Darker #0A0A6E (derived) for text accents. */
.cd-theme #brandChip, .cd-theme #searchPill { color: #0a0a6e; }
.cd-theme .tr-search { background: linear-gradient(180deg, rgba(15, 15, 150, 0.9), rgba(10, 10, 110, 0.9)) !important; }
.cd-theme .tr-pref button.on { background: #0f0f96; }
.cd-theme .sp-row .sp-line { background: #0f0f96; }
.cd-theme .tr-city { color: #0a0a6e !important; }
.cd-theme .tr-swap { color: #0a0a6e; border-color: rgba(15,15,150,0.35); }
.cd-theme .tr-tabs button { color: #0a0a6e; }
.cd-theme .tr-tabs button.on { background: #0f0f96; color: #fff; }
```

### 1d. `data()` — city validator
Add `'cd'` to the allowed list (after `'cc'`).

### 1e. `data()` — city data fields (after the `cc*` fields)
```js
cdStations: (window.CD_STATIONS || []),
cdRoutes: (window.CD_ROUTES || null),
cdLogo: (window.CD_LOGO || ''),
cdMap: (window.CD_MAP || ''),
cdmIcon: (window.CDM_ICON || ''),
cdSplash: (window.CD_SPLASH || ''),
cdTimetable: (window.CD_TIMETABLE || {}),
```

### 1f. `switchCity()` guard + branch (guard after the cc guard, branch after the cc branch, before the final `else`)
Guard:
```js
if (c === 'cd' && (!this.cdStations.length || !this.cdMap)) return;
```
Branch:
```js
} else if (c === 'cd') {
    this.stations = this.cdStations;
    this.routes = this.cdRoutes;
    this.transfers = (window.CD_TRANSFERS || {});
    this.curr = { svgUrl: "", svgDom: this.cdMap, pdfUrl: "", success: true, json: null, verName: "CD", verInfo: "{ " + this.t('map.verInfo', {c: this.t('city.cd'), d: '2026-11', l: 17, s: 364}) + " }", showCmitInfo: false, cmitFixed: "", cmitVar: "" };
```
Note: `window.CD_TRANSFERS` does not exist yet (see "Not yet prepared") — the `|| {}` fallback is required, same as the other cities before their transfers were built.

### 1g. Mount force-switch
Add `'cd'` to the saved-city list (after `'cc'`). (City-persistence fix: the mount must force `switchCity(_savedCity, true)` for any non-Beijing city, otherwise the map stays Beijing even though the pill shows the saved city.)

### 1h. `shScaleFor()` — Chengdu px/km (after the `cc` branch)
Pixel path length per line (sum of Euclidean edge lengths from routes.json edges + stations.json x,y) divided by the real line length (research.json, zh-Wikipedia line table). The scale varies widely because the schematic compresses the express/intercity lines and enlarges the loop — use the per-line values, not a single overall scale (overall is 31.32).
```js
if (this.city === 'cd') {
    // Chengdu px/km = pixel edge length / real line length (see
    // chengdu/NOTES.md). Scale varies widely: the express/intercity
    // lines (18, 19, S3) are drawn compressed and the loop (7) is drawn
    // large. Fares are estimates — error can exceed ±¥1 on those lines.
    var CD = { '1': 36.84, '2': 32.77, '3': 34.34, '4': 34.00,
               '5': 30.35, '6': 31.53, '7': 53.06, '8': 40.62,
               '9': 39.54, '10': 21.85, '13': 36.32, '17': 42.83,
               '18': 13.10, '19': 25.23, '27': 36.92, '30': 47.19,
               'S3': 7.66 };
    return CD[lineKey] || 31.32;
}
```

### 1i. Fare — Chengdu block (after the `cc` fare block)
Same shape as the other cities' blocks: sum `segKm` over `r.segments`, then apply the Chengdu bands (verified, Bendibao reproducing official policy + Trip.com table):
- ≤ 4 km → ¥2
- 4–8 km → ¥3
- 8–12 km → ¥4
- 12–18 km → ¥5
- 18–24 km → ¥6
- 24–32 km → ¥7
- 32–40 km → ¥8
- 40–50 km → ¥9
- 50–70 km → ¥10
- 70–90 km → ¥11
- 90–110 km → ¥12
- 110–130 km → ¥13 (max)

Formula: ¥2 for the first 4 km; +¥1 per 4 km to 12 km; +¥1 per 6 km to 24 km; +¥1 per 8 km to 40 km; +¥1 per 10 km to 50 km; +¥1 per 20 km above 50 km.

Cross-checks the app must reproduce: full Line 2 犀浦—龙泉驿 (42.32 km) = **¥9**; full S3 福田—资阳北站 (38.7 km) = **¥8** (Bendibao states the S3 full-line max fare is ¥8). Intermediate fares are computed from the schematic map scale and are estimates — only these two end-to-end checks are published-verified (the band structure itself is verified). Do NOT present the band-table lookup as exact without real OD distances (see research.json fare note). 9折 applies with the Chengdu Metro app / Tianfutong (do not apply the discount in the fare display unless the other cities do).

### 1j. Transit app id (`openTransitApp()`)
Add the `'cd'` case: `... (this.city === 'cc' ? '1481796811' : (this.city === 'cd' ? '1303414976' : '1071038870'))`. (成都地铁-官方APP, App Store id 1303414976. URL scheme is UNVERIFIED — use the App Store link for the jump row, do not attempt a URL-scheme jump.)

### 1k. City helpers + I18N
`cityName()` / `transitLabel()` already use I18N keys, so add the entries (do not hardcode a ternary):
- `'city.cd': ['成都', '成都', 'Chengdu']` (after `'city.cc'`). (成都 is identical in Simplified and Traditional.)
- `'transit.cd': ['打开成都地铁', '打開成都地鐵', 'Open Chengdu Metro']` (after `'transit.cc'`).
- `cityLogo()`: add `this.cdLogo` (extend the ternary, after the cc case).
- `transitIcon()`: add `this.cdmIcon` (after the cc case).
- `splashImg()`: add `this.cdSplash` (after the cc case).
- City list: add `{ key: 'cd', name: this.t('city.cd') }` (after the cc entry).

### 1l. `timetableData()`
Add `if (this.city === 'cd') return this.cdTimetable;` (after the cc line).

### 1m. tt-note (REQUIRED for cd) + Line 7 loop flag — two items
(a) The Chengdu timetable is **entirely estimated** (derived from official terminus times at 2.0 min/interval — see NOTES.md), so add the span (same pattern as the cc note):
```html
<span v-if="city==='cd'">{{ t('tt.note.cd') }}</span>
```
and the I18N entry (after `'tt.note.cc'`):
```js
'tt.note.cd': ['全线时刻表为估算值（按官方公布的首末班时间，站间约 2 分钟推算；快线 18/19 号线与市域线 S3 的站间用时偏长，误差较大），请以车站公布为准。', '全線時刻表為估算值（按官方公佈的首末班時間，站間約 2 分鐘推算；快線 18/19 號線與市域線 S3 的站間用時偏長，誤差較大），請以車站公佈為準。', 'All times are estimated (official first/last times, ~2 min per stop; express Lines 18/19 and intercity Line S3 take longer per stop, so error is larger). Please follow station notices.'],
```
(b) **Line 7 loop flag**: `template.html` reads `ln.loop` for the timetable direction label. `routes.json` has NO `"loop": true` on Line 7 (Changchun format has no loop flag) — the wiring step must add `"loop": true` to Line 7 in `routes.json` (or handle it in the wiring code) so the timetable shows 环线 instead of 火车北站 — 驷马桥. Also confirm the timetable UI renders Line 1's **3-direction entries** on the shared section 韦家碾–四河 (the data has 韦家碾 / 科学城 / 五根松 as three directions there; if the UI only renders 2 directions per line, decide which southbound destination to show and note it — do not silently drop one).

### 1n. Timetable post-midnight lasts
`cd.json` writes last trains arriving after 00:00 as `00:xx` (80 entries), so first > last numerically for those entries (e.g. 松林 6号线 07:52/00:12). Genuine, not errors — the wiring/verification must NOT cap these at 23:59 and the UI must display them as-is.

## 2. `web/build_offline.py`

### 2a. 成都地铁 app icon (after the `cce_b64` block)
```python
cdm_b64 = (BASE / "cdmetro-icon.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__CDM_ICON__\*/', lambda _: cdm_b64, html, "chengdu metro app icon")
```
(Only if `cdmetro-icon.b64` has been sourced — see "Not yet prepared". If it is still missing, skip this block and use `logo.b64` as the transit-icon fallback; do not block wiring on it.)

### 2b. Chengdu data inline (after the Changchun block)
```python
# S. inline the Chengdu Metro data (17 operating lines, 364 stations).
# Same pattern as Changchun: precomputed stations/routes from the RMP
# Gallery map (see chengdu/NOTES.md); the T2 tram, the 6 built-but-
# unopened stations (白仁店, 玉虹路, 分水, 天府机场3号4号航站楼, 合江,
# 芦葭), the Line 10 third-phase platforms, 18号线三期 and S5/S11 are
# drawn on the map or under construction but are NOT in the data files.
cd_stations = (BASE / "chengdu" / "stations.json").read_text(encoding="utf-8")
cd_routes = (BASE / "chengdu" / "routes.json").read_text(encoding="utf-8")
cd_map = (BASE / "chengdu" / "map.svg").read_text(encoding="utf-8")
cd_logo_b64 = (BASE / "chengdu" / "logo.b64").read_text(encoding="utf-8").strip()
cd_splash_b64 = (BASE / "chengdu" / "splash.b64").read_text(encoding="utf-8").strip()
assert "</script" not in cd_stations, "cd stations json must not contain </script"
assert "</script" not in cd_routes, "cd routes json must not contain </script"
assert "</script" not in cd_map, "cd map svg must not contain </script"
html = sub_once(r'/\*__CD_STATIONS__\*/\[\]', lambda _: cd_stations, html, "cd stations json")
html = sub_once(r'/\*__CD_ROUTES__\*/null', lambda _: cd_routes, html, "cd routes json")
html = sub_once(r'/\*__CD_MAP__\*/""', lambda _: _json.dumps(cd_map), html, "cd map svg")
html = sub_once(r'/\*__CD_LOGO__\*/', lambda _: cd_logo_b64, html, "cd logo")
html = sub_once(r'/\*__CD_SPLASH__\*/', lambda _: cd_splash_b64, html, "cd splash")
```
(If `logo.b64` / `splash.b64` are still missing when wiring, the corresponding `sub_once` lines must wait for those files — do not inline a placeholder and do not skip the assert.)

### 2c. Timetable inline (after the `cc_tt` block)
```python
cd_tt = (BASE / "timetable" / "cd.json").read_text(encoding="utf-8")
assert "</script" not in cd_tt, "cd timetable json must not contain </script"
html = sub_once(r'/\*__CD_TIMETABLE__\*/\{\}', lambda _: cd_tt, html, "cd timetable json")
```

## 3. `app/AppDelegate.swift`

### 3a. Theme colours (near `changchunRed` / `changchunRedDark`)
```swift
// Chengdu Line 1 #0F0F96 (official line colour, Chengdu DB510100/T
// 083-2012 wayfinding standard; no single official system brand colour
// is published). Darker #0A0A6E is derived (Line 1 darkened ~30%), not
// an official published value.
let chengduBlue = UIColor(red: 15.0 / 255.0, green: 15.0 / 255.0, blue: 150.0 / 255.0, alpha: 1)
let chengduBlueDark = UIColor(red: 10.0 / 255.0, green: 10.0 / 255.0, blue: 110.0 / 255.0, alpha: 1)
```

### 3b. I18N (LANG dict, after `"city.cc"`)
```swift
"city.cd": ["成都", "成都", "Chengdu"],
```

### 3c. Restore saved city
Add `"cd"` to the saved-city list (after `"cc"`).

### 3d. Native splash
Add `case "cd": splashName = "SplashCD"` (after the cc case). Requires `SplashCD.jpg` in the bundle (see §4) — which requires a real user splash (see "Not yet prepared").

### 3e. Accent / search button / logo / pill name
- `accentColor()`: `if currentCity == "cd" { return chengduBlue }`.
- `accentDark()`: `if currentCity == "cd" { return chengduBlueDark }`.
- `searchButtonColor()`: `if currentCity == "cd" { return chengduBlue }`.
- `cityLogoImage()`: `case "cd": name = "ChengduLogo"`.
- `updateCityPill()`: `case "cd": name = "成都"` (uses the LANG dict; the pill name comes from `L("city.cd")` — confirm the pattern matches cc).

### 3f. City menu
Add a `cd` UIAction (`title: L("city.cd")`, `pickCity("cd")`) and include it in the `UIMenu` children (order: bj, sy, sh, hb, dl, jh, cz, cq, cc, cd).

### 3g. City sheet
Add `sheet.addAction(cityAction("cd"))` (confirm the `cityAction` helper pattern matches cc).

### 3h. `openTransitApp()`
Add `case "cd": id = "1303414976"` and update the comment (add 成都地铁-官方APP 1303414976 to the verified list). URL scheme is UNVERIFIED — the jump must use the App Store link, not a URL scheme.

### 3i. `cityChanged` handler
Add `"cd"` to the accept list (now `[..., "cq", "cc"]` → `[..., "cq", "cc", "cd"]`).

## 4. `build.sh`

After the Changchun splash line:
```sh
# Chengdu splash (real user splash, web/chengdu/splash.b64).
python3 -c "import base64; open('build/Payload/Metro.app/SplashCD.jpg','wb').write(base64.b64decode(open('web/chengdu/splash.b64').read()))"
```
After the ChangchunLogo line:
```sh
python3 -c "import base64; open('build/Payload/Metro.app/ChengduLogo.png','wb').write(base64.b64decode(open('web/chengdu/logo.b64').read()))"
```
(Both require the files in "Not yet prepared" — do not run these lines until `splash.b64` and `logo.b64` exist. The logo is an SVG from Wikimedia; if the bundle needs a PNG, convert the SVG to PNG first and note the conversion — do not silently substitute a different logo.)

## 5. Build / verify (after wiring)

1. Bump `app/Info.plist` CFBundleVersion to the new build number.
2. Push only sources (never `web/offline/index.html` — push-files rejects it with HTTP 413); trigger one run of **Build Metro IPA**.
3. Download and verify the IPA: `CD_STATIONS`/`CD_TIMETABLE` inlined, `SplashCD.jpg` + `ChengduLogo.png` in the bundle (if those files existed at wiring time), `CFBundleVersion` correct.
4. On-device checks: switch to 成都 — the map shows (not Beijing), 犀浦→龙泉驿 routes with fare ¥9, 福田→资阳北站 fare ¥8, timetable shows estimated first/last (with the tt-note warning visible), transit row says 打开成都地铁, search button is Line 1 blue #0F0F96, tab bar selected state is Line 1 blue, the Line 7 timetable shows 环线 (not 火车北站 — 驷马桥）, the Line 1 shared section shows the branch destinations correctly.
5. Also verify that searching for 白仁店 / 玉虹路 / 分水 / 天府机场3号4号航站楼 / 合江 / 芦葭 / 官堰 / any S5 or S11 station returns NO results (unopened lines/stations must not be searchable), that the T2 tram stations are not searchable, and that switching back to Beijing still works (regression).
6. Verify the two fare cross-checks (犀浦→龙泉驿 ¥9, 福田→资阳北站 ¥8) and note the fare is an estimate.

## Known caveats (from NOTES.md — do not "fix" silently)

- 364 operating stations, not any published "365" (Amap states 365 unique — off by one, likely the transfer-only 天府站 counting; 364 is verified from the 449/85 arithmetic and matches the zh-Wikipedia footnote).
- Line 1 has a branch (四河–广都–五根松）; the routes.json single-list representation follows the Beijing T1 precedent. The timetable gives the shared section 3 direction entries (see §1m).
- Line 7 is a loop; routes.json has no `"loop": true` flag — the wiring step must add it (see §1m).
- Timetable is ENTIRELY estimated (terminus times from secondary sources, 2.0 min/interval interpolation). The official chengdurail.com timetable could not be fetched from this environment — verify before shipping. S3/18/19 are express lines: flat 2.0 min/interval understates travel (S3 end-to-end is ~26 min published vs 10 min interpolated). Lines 10 and 17 short-turns (武侯祠–花桥, 九江北–机车厂） are not modelled (full terminus-to-terminus only). L6 兰家沟 last train uses 22:30 (gzhphb) over dushiquan's implied 22:39 — still needs official verification.
- Fare is an estimate from the schematic map scale; the scale varies widely by line (see §1h), so error can exceed ±¥1 on lines 18/19/S3 and 7. Only the two end-to-end checks are published-verified.
- Lat/lng is 362/364 — 净居寺 and 龙泉驿火车站 have no coordinates (nearby-station sorting will skip them; they are still searchable and routable).
- Map: Line 30 玉石–惠王陵 has no drawn segment in map.svg (cosmetic only). The RMP text metrics are estimated (a pixel-level difference in a few badge/background widths vs a browser export is possible). On-device visual check still needed, same as the other 8 maps.
- Logo is NOT yet downloaded (Wikimedia blocked/429 from this VM) and no user splash has been supplied — both are required before wiring completes (§4, "Not yet prepared").
- `transfers.json` (virtual different-name transfers) is NOT yet prepared for `cd` — wire it later if a transfer agent produces one.
- 天府站 (Lines 18/19) is transfer-only (no entry/exit) — it is in stations.json/routes.json as an interchange; the app does not model entry/exit, so no special handling is needed, but do not treat it as a normal origin/destination for walking directions.
- One name-variant: research.json writes 棬子樹 (traditional 樹); the map writes 棬子树 (simplified). Files use the research spelling 棬子樹 at (95, 285).
