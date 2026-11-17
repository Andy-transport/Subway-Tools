# Wiring Changchun (`cc`) into the app — DO NOT do this until build 66 lands

This file lists the exact edits to wire the prepared Changchun data
(`web/changchun/`, `web/timetable/cc.json`, `web/ccmetro-icon.b64`) into
the app as city `'cc'`. It follows the Harbin (build 59) / Dalian (build
61) / Jinhua / Changzhou / Chongqing pattern exactly. **Wait until build
66 is pushed and its AppDelegate.swift / template.html changes are in**
— build 66 is editing both files in parallel (Search Conditions,
line-named operating-hours, "即将开通", briefing, Siri intents). Rebase
these edits on the build-66 head; line numbers below are from the
current (post-Chongqing) files and WILL shift. Anchor on the `cq`
blocks, not on line numbers.

Files already prepared (do not re-create):
- `web/changchun/stations.json` — 142 stations {n, py, ini, x, y}
- `web/changchun/routes.json` — lines 1–8 (15/27/34/21/18/22/19/12
  stations), 160 edges; 26 interchanges
- `web/changchun/map.svg` — JPEG-in-SVG wrapper, viewBox 0 0 1206 1189
- `web/changchun/logo.b64` — FALLBACK logo: official 长春E出行 app icon
  artwork, 120×120 PNG. Replace with the mark from
  `Changchun_Railway_Traffic_logo.svg` if it becomes downloadable
  (see NOTES.md).
- `web/changchun/splash.b64` — REAL user splash (not a placeholder)
- `web/timetable/cc.json` — first/last times, all 142 stations (L2/L5
  = real per-station tables; L1/L3/L4/L6/L7/L8 = estimated — see
  NOTES.md)
- `web/ccmetro-icon.b64` — 长春E出行 app icon, 120×120 PNG (identical
  bytes to `logo.b64`, same as Changzhou)
- `web/changchun/NOTES.md` — full data documentation

**Not yet prepared**: `web/changchun/transfers.json` (virtual
different-name transfers). The other cities' virtual transfers were
built into run #69; Changchun was skipped (no stations.json yet).
If the transfer subagent produces one, inline it as
`window.CC_TRANSFERS` following the `cq` pattern
(`build_offline.py` lines ~154–163, `template.html` line ~49).
Until then, same-name interchanges route normally and different-name
virtual transfers are not available for `cc`.

## 1. `web/template.html`

### 1a. Global placeholders (after the CQ ones, lines ~38–41, 59, 67, 75)
```js
window.CC_STATIONS = /*__CC_STATIONS__*/[];
window.CC_ROUTES = /*__CC_ROUTES__*/null;
window.CC_MAP = /*__CC_MAP__*/"";
window.CC_LOGO = "data:image/png;base64,/*__CC_LOGO__*/";
window.CCE_ICON = "data:image/png;base64,/*__CCE_ICON__*/";
window.CC_SPLASH = "data:image/png;base64,/*__CC_SPLASH__*/";
window.CC_TIMETABLE = /*__CC_TIMETABLE__*/{};
```

### 1b. Root div theme class (line ~864)
Add `'cc-theme': city === 'cc'` to the `:class` binding (after `'cq-theme'`).

### 1c. CSS — add after the `.cq-theme` rules (after line ~400)
```css
/* Changchun theme: Line 1 red #E50011 (Wikipedia Template:长春轨道交通颜色,
   code 1; no separate system brand colour is published — see NOTES.md).
   Darker #B3000D for text accents. */
.cc-theme #brandChip, .cc-theme #searchPill { color: #b3000d; }
.cc-theme .tr-search { background: linear-gradient(180deg, rgba(229, 0, 17, 0.9), rgba(179, 0, 13, 0.9)) !important; }
.cc-theme .tr-pref button.on { background: #e50011; }
.cc-theme .sp-row .sp-line { background: #e50011; }
.cc-theme .tr-city { color: #b3000d !important; }
.cc-theme .tr-swap { color: #b3000d; border-color: rgba(229,0,17,0.35); }
.cc-theme .tr-tabs button { color: #b3000d; }
.cc-theme .tr-tabs button.on { background: #e50011; color: #fff; }
```

### 1d. `data()` — city validator (line ~1518)
Add `'cc'` to the allowed list: `(c === 'sy' || c === 'sh' || c === 'hb' || c === 'dl' || c === 'jh' || c === 'cz' || c === 'cq' || c === 'cc' || c === 'bj')`.

### 1e. `data()` — city data fields (after the `cq*` fields, lines ~1572–1578)
```js
ccStations: (window.CC_STATIONS || []),
ccRoutes: (window.CC_ROUTES || null),
ccLogo: (window.CC_LOGO || ''),
ccMap: (window.CC_MAP || ''),
cceIcon: (window.CCE_ICON || ''),
ccSplash: (window.CC_SPLASH || ''),
ccTimetable: (window.CC_TIMETABLE || {}),
```

### 1f. `switchCity()` guard + branch (guard line ~1786, branch line ~1840)
Guard (after the cq guard):
```js
if (c === 'cc' && (!this.ccStations.length || !this.ccMap)) return;
```
Branch (after the cq branch, before the final `else`):
```js
} else if (c === 'cc') {
    this.stations = this.ccStations;
    this.routes = this.ccRoutes;
    this.curr = { svgUrl: "", svgDom: this.ccMap, pdfUrl: "", success: true, json: null, verName: "CC", verInfo: "{ " + this.t('map.verInfo', {c: this.t('city.cc'), d: '2026-11', l: 8, s: 142}) + " }", showCmitInfo: false, cmitFixed: "", cmitVar: "" };
```

### 1g. Mount force-switch (line ~3099)
Add `'cc'` to the list: `if (_savedCity === 'sy' || _savedCity === 'sh' || _savedCity === 'hb' || _savedCity === 'dl' || _savedCity === 'jh' || _savedCity === 'cz' || _savedCity === 'cq' || _savedCity === 'cc') {`. (This is the city-persistence fix: the mount must force `switchCity(_savedCity, true)` for any non-Beijing city, otherwise the map stays Beijing even though the pill shows the saved city.)

### 1h. `shScaleFor()` — Changchun px/km (after the `cq` branch, ~line 2163)
```js
if (this.city === 'cc') {
    // Changchun px/km = pixel path length / real line length (Wikipedia;
    // see changchun/NOTES.md). The map is schematic; scale varies by
    // line (28.7–35.8). Fare error from scale variation is typically ±¥1.
    var CC = { '1': 35.14, '2': 31.99, '3': 33.44, '4': 34.92,
               '5': 32.95, '6': 34.15, '7': 35.81, '8': 28.69 };
    return CC[lineKey] || 33.5;
}
```

### 1i. Fare — Changchun block (after the `cq` fare block, ~line 2331)
Same shape as the other cities' blocks: sum `segKm` over `r.segments`,
then apply the Changchun bands (verified, Wikipedia 票价):
- ≤ 7 km → ¥2
- 7–13 km → ¥3
- 13–19 km → ¥4
- 19–27 km → ¥5
- 27–35 km → ¥6
- > 35 km → ¥6 + ceil((km − 35) / 10)

Cross-check the app must reproduce: full L2 汽车公园—雾开河大街
(35.5 km) = **¥7** (just over the 35 km band edge). Intermediate fares
are computed from the schematic map scale and are estimates — only the
¥7 end-to-end check is published-verified (the band structure itself
is verified from Wikipedia).

### 1j. Transit app id (line ~2409, `openTransitApp()`)
Add the `'cc'` case: `... (this.city === 'cq' ? '1491110313' : (this.city === 'cc' ? '1481796811' : '1071038870'))`. (长春E出行, App Store id 1481796811.)

### 1k. City helpers + I18N (lines ~2917–2934, ~1262–1269, ~1332–1339)
`cityName()` / `transitLabel()` already use I18N keys, so add the
entries (do not hardcode a ternary):
- `'city.cc': ['长春', '長春', 'Changchun']` (after `'city.cq'`, line ~1339).
- `'transit.cc': ['打开长春E出行', '打開長春E出行', 'Open Changchun E-Travel']` (after `'transit.cq'`, line ~1269).
- `cityLogo()`: add `this.ccLogo` (extend the ternary, after the cq case).
- `transitIcon()`: add `this.cceIcon` (after the cq case).
- `splashImg()`: add `this.ccSplash` (after the cq case).
- City list (line ~2922): add `{ key: 'cc', name: this.t('city.cc') }` (after the cq entry).

### 1l. `timetableData()` (line ~2949)
Add `if (this.city === 'cc') return this.ccTimetable;` (after the cq line).

### 1m. tt-note (line ~974 + I18N lines ~1205–1209) — REQUIRED for cc
The Changchun timetable is **partly estimated** (L2/L5 real, the other
six lines estimated — see NOTES.md), so add the span:
```html
<span v-if="city==='cc'">{{ t('tt.note.cc') }}</span>
```
and the I18N entry (after `'tt.note.cq'`):
```js
'tt.note.cc': ['2、5号线为官方逐站时刻表；其余线路为估算值（首末班时间按官方公布，站间约 2 分钟推算；冬季时刻），请以车站公布为准。', '2、5號線為官方逐站時刻表；其餘線路為估算值（首末班時間按官方公佈，站間約 2 分鐘推算；冬季時刻），請以車站公佈為準。', 'Lines 2 and 5 use the official per-station timetable; other lines are estimated (official first/last times, ~2 min per stop; winter timetable). Please follow station notices.'],
```

## 2. `web/build_offline.py`

### 2a. 长春E出行 icon (after the `ycx_b64` block, ~line 183)
```python
cce_b64 = (BASE / "ccmetro-icon.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__CCE_ICON__\*/', lambda _: cce_b64, html, "changchun e-travel icon")
```

### 2b. Changchun data inline (after the Chongqing block, ~line 294)
```python
# S. inline the Changchun Rail Transit data (8 operating lines, 142 stations).
# Same pattern as Harbin/Dalian/Jinhua/Changzhou/Chongqing: precomputed
# stations/routes from the user's schematic map (see changchun/NOTES.md);
# Line 9, the L3 天泽大路 extension, the L1 southern extension and the
# closed 辽宁路 are drawn on the map but are NOT in the data files.
cc_stations = (BASE / "changchun" / "stations.json").read_text(encoding="utf-8")
cc_routes = (BASE / "changchun" / "routes.json").read_text(encoding="utf-8")
cc_map = (BASE / "changchun" / "map.svg").read_text(encoding="utf-8")
cc_logo_b64 = (BASE / "changchun" / "logo.b64").read_text(encoding="utf-8").strip()
cc_splash_b64 = (BASE / "changchun" / "splash.b64").read_text(encoding="utf-8").strip()
assert "</script" not in cc_stations, "cc stations json must not contain </script"
assert "</script" not in cc_routes, "cc routes json must not contain </script"
assert "</script" not in cc_map, "cc map svg must not contain </script"
html = sub_once(r'/\*__CC_STATIONS__\*/\[\]', lambda _: cc_stations, html, "cc stations json")
html = sub_once(r'/\*__CC_ROUTES__\*/null', lambda _: cc_routes, html, "cc routes json")
html = sub_once(r'/\*__CC_MAP__\*/""', lambda _: _json.dumps(cc_map), html, "cc map svg")
html = sub_once(r'/\*__CC_LOGO__\*/', lambda _: cc_logo_b64, html, "cc logo")
html = sub_once(r'/\*__CC_SPLASH__\*/', lambda _: cc_splash_b64, html, "cc splash")
```

### 2c. Timetable inline (after the `cq_tt` block, ~line 317)
```python
cc_tt = (BASE / "timetable" / "cc.json").read_text(encoding="utf-8")
assert "</script" not in cc_tt, "cc timetable json must not contain </script"
html = sub_once(r'/\*__CC_TIMETABLE__\*/\{\}', lambda _: cc_tt, html, "cc timetable json")
```

## 3. `app/AppDelegate.swift`

### 3a. Theme colours (near `chongqingGreen` / `chongqingGreenDark`)
```swift
// Changchun Line 1 red #E50011 (Wikipedia Template:长春轨道交通颜色,
// code 1; no separate system brand colour is published — see NOTES.md).
// Darker #B3000D for selected states/text.
let changchunRed = UIColor(red: 229.0 / 255.0, green: 0.0 / 255.0, blue: 17.0 / 255.0, alpha: 1)
let changchunRedDark = UIColor(red: 179.0 / 255.0, green: 0.0 / 255.0, blue: 13.0 / 255.0, alpha: 1)
```

### 3b. I18N (LANG dict, after `"city.cq"`, ~line 185)
```swift
"city.cc": ["长春", "長春", "Changchun"],
```

### 3c. Restore saved city (line ~265)
Add `"cc"` to `["bj", "sy", "sh", "hb", "dl", "jh", "cz", "cq"]`.

### 3d. Native splash (line ~418)
Add `case "cc": splashName = "SplashCC"` (after the cq case).

### 3e. Accent / search button / logo / pill name
- `accentColor()` (~line 513): `if currentCity == "cc" { return changchunRed }`.
- `accentDark()` (~line 526): `if currentCity == "cc" { return changchunRedDark }`.
- `searchButtonColor()` (~line 542): `if currentCity == "cc" { return changchunRed }`.
- `cityLogoImage()` (~line 563): `case "cc": name = "ChangchunLogo"`.
- `updateCityPill()`: `case "cc": name = "长春"` (uses the LANG dict; the
  pill name comes from `L("city.cc")` — confirm the pattern matches cq).

### 3f. City menu (lines ~660–663)
Add a `cc` UIAction (`title: L("city.cc")`, `pickCity("cc")`) and include
it in the `UIMenu` children (order: bj, sy, sh, hb, dl, jh, cz, cq, cc).

### 3g. City sheet (line ~690)
Add `sheet.addAction(cityAction("cc"))` (confirm the `cityAction`
helper pattern matches cq).

### 3h. `openTransitApp()` (line ~1440)
Add `case "cc": id = "1481796811"` and update the comment (add
长春E出行 1481796811 to the verified list).

### 3i. `cityChanged` handler (line ~1856)
Add `"cc"` to the accept list, which is now
`["bj", "sy", "sh", "hb", "dl", "jh", "cz", "cq"]` (the old gap is
already fixed) → `["bj", "sy", "sh", "hb", "dl", "jh", "cz", "cq", "cc"]`.

## 4. `build.sh`

After the Chongqing splash line (~line 74):
```sh
# Changchun splash (real user splash, web/changchun/splash.b64).
python3 -c "import base64; open('build/Payload/Metro.app/SplashCC.jpg','wb').write(base64.b64decode(open('web/changchun/splash.b64').read()))"
```
After the ChongqingLogo line (~line 80):
```sh
python3 -c "import base64; open('build/Payload/Metro.app/ChangchunLogo.png','wb').write(base64.b64decode(open('web/changchun/logo.b64').read()))"
```

## 5. Build / verify (after wiring)

1. Bump `app/Info.plist` CFBundleVersion to the new build number.
2. Push only sources (never `web/offline/index.html` — push-files rejects
   it with HTTP 413); trigger one run of **Build Metro IPA**.
3. Download and verify the IPA: `CC_STATIONS`/`CC_TIMETABLE` inlined,
   `SplashCC.jpg` + `ChangchunLogo.png` in the bundle, `CFBundleVersion`
   correct.
4. On-device checks: switch to 长春 — the map shows (not Beijing),
   汽车公园→雾开河大街 routes, fare ¥7, timetable shows real first/last
   (汽车公园往雾开河大街 05:15/22:05; 雾开河大街往汽车公园 05:45/22:05),
   transit row says 打开长春E出行, search button is Line 1 red #E50011,
   tab bar selected state is Line 1 red, the tt-note shows the estimate
   warning.
5. Also verify that searching for 天津大路 / 交通大路 / 红石 / 兴创路 /
   辽宁路 / 9号线 returns NO results (unopened lines/stations must not
   be searchable), and that switching back to Beijing still works
   (regression).

## Known caveats (from NOTES.md — do not "fix" silently)

- 142 operating stations, not the published "167" (that count is from
  2026-09, before 长影旧址博物馆 opened 2026-10-22; L5 is 18, not 17).
- Line 9, the L3 天泽大路 extension, the L1 southern extension and
  辽宁路 are drawn on the map image but are NOT in stations.json /
  routes.json / cc.json and must never be searchable or routable. The
  image still shows them (cosmetic caveat).
- Timetable is WINTER times; L2/L5 are real per-station tables, the
  other six lines are estimated (2.0 min/interval from the official
  terminus times; L3 first trains capped at 06:07 for the mid-line
  05:55 origins; L6 uses the real 福祉大路 05:18 mid-line origin).
  Summer last trains are 30 min later on most lines.
- Several coordinates are interpolated / crossing-derived (listed in
  NOTES.md) — validated by numbered overlay, not fabricated.
- Logo is a fallback from the official 长春E出行 app icon artwork (the
  SVG was undownloadable from this VM); replace with the
  `Changchun_Railway_Traffic_logo.svg` mark if obtainable.
- Splash is the real user splash (not a placeholder).
- `transfers.json` (virtual different-name transfers) is NOT yet
  prepared for `cc` — wire it later if the transfer subagent produces
  one.
- Zoom will blur (JPEG-in-SVG, same as the other raster cities).
