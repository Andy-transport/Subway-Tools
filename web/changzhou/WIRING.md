# Wiring Changzhou (`cz`) into the app — DO NOT do this until build 66 lands

This file lists the exact edits to wire the prepared Changzhou data
(`web/changzhou/`, `web/timetable/cz.json`, `web/czmetro-icon.b64`) into the
app as city `'cz'`. It follows the Harbin (build 59) / Dalian (build 61) /
Jinhua pattern exactly. **Wait until build 66 is pushed and its
AppDelegate.swift / template.html changes are in** — build 66 is editing
both files in parallel (Search Conditions, line-named operating-hours,
"即将开通", briefing, Siri intents). Rebase these edits on the build-66
head; line numbers below are from the pre-build-66 files and WILL shift.

Files already prepared (do not re-create):
- `web/changzhou/stations.json` — 43 stations {n, py, ini, x, y}
- `web/changzhou/routes.json` — lines 1 (29 stations) + 2 (15 stations),
  42 edges; 文化宫 is the shared interchange
- `web/changzhou/map.svg` — JPEG-in-SVG wrapper, viewBox 0 0 1206 1419
- `web/changzhou/logo.b64` — FALLBACK logo: official 常州地铁Metro app
  icon artwork (white mark on brand red), 120×120 PNG. Replace with the
  mark from `ChangzhouMetro.svg` if it becomes downloadable (see NOTES.md).
- `web/changzhou/splash.b64` — PLACEHOLDER splash (map image on a white
  1170×2532 canvas); replace if the user sends a real Changzhou splash
- `web/timetable/cz.json` — first/last times, all 43 stations (Line 2
  lasts = official image; Line 1 lasts = dushiquan + 30 min — see NOTES.md
  open question)
- `web/czmetro-icon.b64` — 常州地铁Metro app icon, 120×120 PNG
- `web/changzhou/NOTES.md` — full data documentation

## 1. `web/template.html`

### 1a. Global placeholders (near lines 22–47, next to the HB/DL/JH ones)
```js
window.CZ_STATIONS = /*__CZ_STATIONS__*/[];
window.CZ_ROUTES = /*__CZ_ROUTES__*/null;
window.CZ_MAP = /*__CZ_MAP__*/"";
window.CZ_LOGO = "data:image/png;base64,/*__CZ_LOGO__*/";
window.CZM_ICON = "data:image/png;base64,/*__CZM_ICON__*/";
window.CZ_SPLASH = "data:image/png;base64,/*__CZ_SPLASH__*/";
window.CZ_TIMETABLE = /*__CZ_TIMETABLE__*/{};
```

### 1b. Root div theme class (line ~646)
Add `'cz-theme': city === 'cz'` to the `:class` binding (after `'jh-theme'`).

### 1c. CSS — add after the `.jh-theme` rules (after line ~331)
```css
/* Changzhou theme: brand red #CD5C5C (Wikipedia Template:常州地铁颜色,
   code 1). Darker #A04848 for text accents. */
.cz-theme #brandChip, .cz-theme #searchPill { color: #a04848; }
.cz-theme .tr-search { background: linear-gradient(180deg, rgba(205, 92, 92, 0.9), rgba(160, 72, 72, 0.9)) !important; }
.cz-theme .tr-pref button.on { background: #cd5c5c; }
.cz-theme .sp-row .sp-line { background: #cd5c5c; }
.cz-theme .tr-city { color: #a04848 !important; }
.cz-theme .tr-swap { color: #a04848; border-color: rgba(205,92,92,0.35); }
.cz-theme .tr-tabs button { color: #a04848; }
.cz-theme .tr-tabs button.on { background: #cd5c5c; color: #fff; }
```

### 1d. `data()` — city validator (line ~1024)
Add `'cz'` to the allowed list: `(c === 'sy' || c === 'sh' || c === 'hb' || c === 'dl' || c === 'jh' || c === 'cz' || c === 'bj')`.

### 1e. `data()` — city data fields (after the `jh*` fields, lines ~1056–1062)
```js
czStations: (window.CZ_STATIONS || []),
czRoutes: (window.CZ_ROUTES || null),
czLogo: (window.CZ_LOGO || ''),
czMap: (window.CZ_MAP || ''),
czmIcon: (window.CZM_ICON || ''),
czSplash: (window.CZ_SPLASH || ''),
czTimetable: (window.CZ_TIMETABLE || {}),
```

### 1f. `switchCity()` guard + branch (lines ~1182–1200)
Guard (after the jh guard):
```js
if (c === 'cz' && (!this.czStations.length || !this.czMap)) return;
```
Branch (after the jh branch, before the final `else`):
```js
} else if (c === 'cz') {
    this.stations = this.czStations;
    this.routes = this.czRoutes;
    this.curr = { svgUrl: "", svgDom: this.czMap, pdfUrl: "", success: true, json: null, verName: "CZ", verInfo: "{ 常州地铁 , 2026-11 , 2条线 43站 }", showCmitInfo: false, cmitFixed: "", cmitVar: "" };
```

### 1g. Mount force-switch (line ~2034)
Add `'cz'` to the list: `if (_savedCity === 'sy' || _savedCity === 'sh' || _savedCity === 'hb' || _savedCity === 'dl' || _savedCity === 'jh' || _savedCity === 'cz') {`. (This is the city-persistence fix: the mount must force `switchCity(_savedCity, true)` for any non-Beijing city, otherwise the map stays Beijing even though the pill shows the saved city.)

### 1h. `shScaleFor()` — Changzhou px/km (after the `jh` branch, ~line 1570)
```js
if (this.city === 'cz') {
    // Changzhou px/km, solved from the real line lengths (Wikipedia) over
    // the map pixel path (station-to-station pixel distances): L1 38.12
    // (1305.2 px / 34.24 km), L2 42.22 (835.5 px / 19.79 km).
    if (lineKey === '1') return 38.12;
    return 42.22;
}
```

### 1i. Fare — Changzhou block (after the `jh` fare block, ~line 1570)
Same shape as the Harbin/Dalian/Jinhua blocks: sum `segKm` over
`r.segments`, then apply the Changzhou bands (verified, Wikipedia 票务 +
本地宝）:
- ≤ 5 km → ¥2
- 5–10 km → ¥3
- 10–15 km → ¥4
- 15–22 km → ¥5
- 22–29 km → ¥6
- > 29 km → ¥6 + ceil((km − 29) / 9)

Cross-check the app must reproduce (published): 森林公园—南夏墅 ¥7
(34.24 km). Intermediate fares (e.g. 文化宫—南夏墅 ≈ 16.3 km → ¥5) are
computed from the schematic scale and are estimates — only the ¥7
end-to-end check is published-verified.

### 1j. Transit app id (line ~1630, `openTransitApp()`)
Add the `'cz'` case: `... (this.city === 'jh' ? '6503238645' : (this.city === 'cz' ? '1474201266' : '1071038870'))`. (常州地铁Metro, App Store id 1474201266.)

### 1k. City helpers (lines ~1884–1888)
- `cityName()`: add `'cz' ? '常州'` (before the final `'北京'`).
- `cityLogo()`: add `this.czLogo`.
- `transitLabel()`: add `'打开常州地铁'`.
- `transitIcon()`: add `this.czmIcon`.
- `splashImg()`: add `this.czSplash`.

### 1l. `timetableData()` (lines ~1899–1901)
Add `if (this.city === 'cz') return this.czTimetable;` (after the jh line).

### 1m. tt-note (line ~755)
No Changzhou span needed — the timetable is real per-station times, not
estimated. The Line 1 +30 min shift is documented in NOTES.md; do not add
an estimate note.

## 2. `web/build_offline.py`

### 2a. 常州地铁Metro icon (after the `rwx_b64` block, ~line 158)
```python
czm_b64 = (BASE / "czmetro-icon.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__CZM_ICON__\*/', lambda _: czm_b64, html, "changzhou metro icon")
```

### 2b. Changzhou data inline (after the Jinhua block, ~line 224)
```python
# S. inline the Changzhou Metro data (2 operating lines, 43 stations).
# Same pattern as Harbin/Dalian/Jinhua: precomputed stations/routes from
# the user's schematic map (see changzhou/NOTES.md); Lines 5/6 are drawn
# on the map but under construction and are NOT in the data files.
cz_stations = (BASE / "changzhou" / "stations.json").read_text(encoding="utf-8")
cz_routes = (BASE / "changzhou" / "routes.json").read_text(encoding="utf-8")
cz_map = (BASE / "changzhou" / "map.svg").read_text(encoding="utf-8")
cz_logo_b64 = (BASE / "changzhou" / "logo.b64").read_text(encoding="utf-8").strip()
cz_splash_b64 = (BASE / "changzhou" / "splash.b64").read_text(encoding="utf-8").strip()
assert "</script" not in cz_stations, "cz stations json must not contain </script"
assert "</script" not in cz_routes, "cz routes json must not contain </script"
assert "</script" not in cz_map, "cz map svg must not contain </script"
html = sub_once(r'/\*__CZ_STATIONS__\*/\[\]', lambda _: cz_stations, html, "cz stations json")
html = sub_once(r'/\*__CZ_ROUTES__\*/null', lambda _: cz_routes, html, "cz routes json")
html = sub_once(r'/\*__CZ_MAP__\*/""', lambda _: _json.dumps(cz_map), html, "cz map svg")
html = sub_once(r'/\*__CZ_LOGO__\*/', lambda _: cz_logo_b64, html, "cz logo")
html = sub_once(r'/\*__CZ_SPLASH__\*/', lambda _: cz_splash_b64, html, "cz splash")
```

### 2c. Timetable inline (after the `jh_tt` block, ~line 232)
```python
cz_tt = (BASE / "timetable" / "cz.json").read_text(encoding="utf-8")
assert "</script" not in cz_tt, "cz timetable json must not contain </script"
html = sub_once(r'/\*__CZ_TIMETABLE__\*/\{\}', lambda _: cz_tt, html, "cz timetable json")
```

## 3. `app/AppDelegate.swift`

### 3a. Theme colours (near `jinhuaRed` / `jinhuaRedDark`, lines ~113–120)
```swift
// Changzhou brand red #CD5C5C (Wikipedia Template:常州地铁颜色, code 1).
// Darker #A04848 for selected states/text.
let changzhouRed = UIColor(red: 205.0 / 255.0, green: 92.0 / 255.0, blue: 92.0 / 255.0, alpha: 1)
let changzhouRedDark = UIColor(red: 160.0 / 255.0, green: 72.0 / 255.0, blue: 72.0 / 255.0, alpha: 1)
```

### 3b. Restore saved city (line ~155)
Add `"cz"` to `["bj", "sy", "sh", "hb", "dl", "jh"]`.

### 3c. Native splash (line ~301)
Add `case "cz": splashName = "SplashCZ"` (after the jh case).

### 3d. Accent / search button / logo / pill name
- `accentColor()` (~line 393): `if currentCity == "cz" { return changzhouRed }`.
- `accentDark()` (~line 403): `if currentCity == "cz" { return changzhouRedDark }`.
- `searchButtonColor()` (~line 416): `if currentCity == "cz" { return changzhouRed }`.
- `cityLogoImage()` (~line 426): `case "cz": name = "ChangzhouLogo"`.
- `updateCityPill()` (~line 443): `case "cz": name = "常州"`.

### 3e. City menu (lines ~500–506)
Add a `cz` UIAction (`title: "常州"`, `pickCity("cz")`) and include it in
the `UIMenu` children (order: bj, sy, sh, hb, dl, jh, cz).

### 3f. City sheet (lines ~523–527)
Add `sheet.addAction(UIAlertAction(title: currentCity == "cz" ? "✓ 常州" : "常州", style: .default) { [weak self] _ in self?.pickCity("cz") })`.

### 3g. `openTransitApp()` (line ~1268)
Add `case "cz": id = "1474201266"` and update the comment (add 常州地铁Metro 1474201266 to the verified list).

### 3h. `cityChanged` handler (line ~1511) — KNOWN GAP, fix while here
The handler's accept list is still `["bj", "sy", "sh"]` — Harbin, Dalian
and Jinhua are missing too, so a web-initiated switch to hb/dl/jh/cz is
not mirrored natively (cosmetic: native tint/pills lag until the next
native action). Change the list to
`["bj", "sy", "sh", "hb", "dl", "jh", "cz"]`.

## 4. `build.sh`

After the Jinhua splash line (~line 57):
```sh
# Changzhou splash (placeholder built from the map image, web/changzhou/splash.b64).
python3 -c "import base64; open('build/Payload/Metro.app/SplashCZ.jpg','wb').write(base64.b64decode(open('web/changzhou/splash.b64').read()))"
```
After the JinhuaLogo line (~line 60):
```sh
python3 -c "import base64; open('build/Payload/Metro.app/ChangzhouLogo.png','wb').write(base64.b64decode(open('web/changzhou/logo.b64').read()))"
```

## 5. Build / verify (after wiring)

1. Bump `app/Info.plist` CFBundleVersion to the new build number.
2. Push only sources (never `web/offline/index.html` — push-files rejects
   it with HTTP 413); trigger one run of **Build Metro IPA**.
3. Download and verify the IPA: `CZ_STATIONS`/`CZ_TIMETABLE` inlined,
   `SplashCZ.jpg` + `ChangzhouLogo.png` in the bundle, `CFBundleVersion`
   correct.
4. On-device checks: switch to 常州 — the map shows (not Beijing),
   森林公园→南夏墅 routes, fare ¥7, timetable shows real first/last
   (森林公园往南夏墅 06:00/22:30, 文化宫往南夏墅 06:11/23:01), transit row
   says 打开常州地铁, search button is brand red #CD5C5C, tab bar selected
   state is brand red.
5. Also verify the fare cross-check (1i), that searching for 揽月湾 / 东青
   (Line 5) and 长江北路 (Line 6) returns NO results (unopened lines must
   not be searchable), and that switching back to Beijing still works
   (regression).

## Known caveats (from NOTES.md — do not "fix" silently)

- 43 operating stations, not the published "44" on some sites (that count
  double-counts 文化宫）.
- Lines 5 and 6 are drawn on the map image but under construction; they
  are NOT in stations.json / routes.json / cz.json and must never be
  searchable or routable. The image still shows them (cosmetic caveat).
- Line 1 last trains = dushiquan + 30 min (2025 adjustment, termini
  22:30). This is inferred from the terminus reports, not a per-station
  published table — replace with a per-station table if one is found.
- All 43 coordinates are machine-detected white dots, validated by
  numbered overlay — no fabrication.
- Splash is a placeholder from the map image; replace if the user sends
  a dedicated Changzhou splash.
- Logo is a fallback from the official app icon artwork (the SVG was
  undownloadable from this VM); replace with the `ChangzhouMetro.svg`
  mark if obtainable.
- Zoom will blur (JPEG-in-SVG, same as the other raster cities).
