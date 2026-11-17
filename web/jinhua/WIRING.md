# Wiring Jinhua (`jh`) into the app — DO NOT do this until build 63 lands

This file lists the exact edits to wire the prepared Jinhua data
(`web/jinhua/`, `web/timetable/jh.json`, `web/renwoxing-icon.b64`) into the
app as city `'jh'`. It follows the Harbin (build 59) / Dalian (build 61)
pattern exactly. **Wait until build 63 is pushed and its AppDelegate.swift
/ template.html changes are in** — build 63 is editing both files in
parallel (Duo sidebar, iPad floating tab bar, WeChat 乘车码). Rebase these
edits on the build-63 head; line numbers below are from the pre-build-63
files and WILL shift.

Files already prepared (do not re-create):
- `web/jinhua/stations.json` — 29 stations {n, py, ini, x, y}
- `web/jinhua/routes.json` — lines JY (16 stations) + YD (14 stations),
  28 edges; 秦塘 is the shared interchange
- `web/jinhua/map.svg` — JPEG-in-SVG wrapper, viewBox 0 0 1206 827
- `web/jinhua/logo.b64` — official logo swoosh, 120×120 PNG
- `web/jinhua/splash.b64` — PLACEHOLDER splash (map image on a white
  1170×2532 canvas); replace if the user sends a real Jinhua splash
- `web/timetable/jh.json` — REAL first/last times, all 29 stations
- `web/renwoxing-icon.b64` — 任我行 app icon, 120×120 PNG
- `web/jinhua/NOTES.md` — full data documentation

## 1. `web/template.html`

### 1a. Global placeholders (near lines 22–47, next to the HB/DL ones)
```js
window.JH_STATIONS = /*__JH_STATIONS__*/[];
window.JH_ROUTES = /*__JH_ROUTES__*/null;
window.JH_MAP = /*__JH_MAP__*/"";
window.JH_LOGO = "data:image/png;base64,/*__JH_LOGO__*/";
window.RWX_ICON = "data:image/png;base64,/*__RWX_ICON__*/";
window.JH_SPLASH = "data:image/png;base64,/*__JH_SPLASH__*/";
window.JH_TIMETABLE = /*__JH_TIMETABLE__*/{};
```

### 1b. Root div theme class (line ~646)
Add `'jh-theme': city === 'jh'` to the `:class` binding (after `'dl-theme'`).

### 1c. CSS — add after the `.dl-theme` rules (after line ~331)
```css
/* Jinhua theme: brand dark red #D8273D (Wikipedia Template:金华轨道交通颜色,
   code JYD). Darker #A81E30 for text accents. */
.jh-theme #brandChip, .jh-theme #searchPill { color: #a81e30; }
.jh-theme .tr-search { background: linear-gradient(180deg, rgba(216, 39, 61, 0.9), rgba(168, 30, 48, 0.9)) !important; }
.jh-theme .tr-pref button.on { background: #d8273d; }
.jh-theme .sp-row .sp-line { background: #d8273d; }
.jh-theme .tr-city { color: #a81e30 !important; }
.jh-theme .tr-swap { color: #a81e30; border-color: rgba(216,39,61,0.35); }
.jh-theme .tr-tabs button { color: #a81e30; }
.jh-theme .tr-tabs button.on { background: #d8273d; color: #fff; }
```

### 1d. `data()` — city validator (line ~1024)
Add `'jh'` to the allowed list: `(c === 'sy' || c === 'sh' || c === 'hb' || c === 'dl' || c === 'jh' || c === 'bj')`.

### 1e. `data()` — city data fields (after the `dl*` fields, lines ~1056–1062)
```js
jhStations: (window.JH_STATIONS || []),
jhRoutes: (window.JH_ROUTES || null),
jhLogo: (window.JH_LOGO || ''),
jhMap: (window.JH_MAP || ''),
rwxIcon: (window.RWX_ICON || ''),
jhSplash: (window.JH_SPLASH || ''),
jhTimetable: (window.JH_TIMETABLE || {}),
```

### 1f. `switchCity()` guard + branch (lines ~1182–1200)
Guard (after the dl guard):
```js
if (c === 'jh' && (!this.jhStations.length || !this.jhMap)) return;
```
Branch (after the dl branch, before the final `else`):
```js
} else if (c === 'jh') {
    this.stations = this.jhStations;
    this.routes = this.jhRoutes;
    this.curr = { svgUrl: "", svgDom: this.jhMap, pdfUrl: "", success: true, json: null, verName: "JH", verInfo: "{ 金华轨道交通金义东线 , 2026-11 , 2条线 29站 }", showCmitInfo: false, cmitFixed: "", cmitVar: "" };
```

### 1g. Mount force-switch (line ~2034)
Add `'jh'` to the list: `if (_savedCity === 'sy' || _savedCity === 'sh' || _savedCity === 'hb' || _savedCity === 'dl' || _savedCity === 'jh') {`. (This is the city-persistence fix: the mount must force `switchCity(_savedCity, true)` for any non-Beijing city, otherwise the map stays Beijing even though the pill shows the saved city.)

### 1h. `shScaleFor()` — Jinhua px/km (after the `dl` branch, ~line 1570)
```js
if (this.city === 'jh') {
    // Jinhua px/km, solved from the real chainage (Wikipedia) over the
    // map pixel path (station-to-station pixel distances, NOT the
    // centreline arc length, which overstates it): JY 11.90,
    // YD main arm (秦塘→明清宫) 13.06.
    // The short 义乌 arm (秦塘→义乌高铁站) is drawn stretched at 19.06;
    // its segments have midpoints above y=422 (junction 秦塘 is at
    // (705,428); the nearest JY midpoint is 绣湖–秦塘 at y=428.5).
    if (lineKey === 'JY') return 11.90;
    if (lineKey === 'YD' && my < 422) return 19.06;
    return 13.06;
}
```
(Simpler alternative: a single YD value of 13.06. The fare error from the
stretched 义乌 arm is ≤ ¥1, usually ¥0, because the fare bands are coarse.
Prefer the midpoint version above — it is exact and only 3 lines.)

### 1i. Fare — Jinhua block (after the `dl` fare block, ~line 1570)
Same shape as the Harbin/Dalian blocks: sum `segKm` over `r.segments`,
then apply the Jinhua bands (verified, Wikipedia 票务):
- ≤ 8 km → ¥2
- 8–28 km → 2 + ceil((km − 8) / 4)
- 28–64 km → 7 + ceil((km − 28) / 6)   (2 + 5 = 7 at 28 km)
- 64 km+  → 13 + ceil((km − 64) / 8)  (2 + 5 + 6 = 13 at 64 km)

Cross-checks the app must reproduce (from the published table):
金华站—秦塘 ¥12 · 金华站—明清宫 ¥17 · 金华站—体育馆 ¥16 ·
凌云—明清宫 ¥10.

### 1j. Transit app id (line ~1630, `openTransitApp()`)
Add the `'jh'` case: `... (this.city === 'dl' ? '1383655806' : (this.city === 'jh' ? '6503238645' : '1071038870'))`. (任我行, App Store id 6503238645.)

### 1k. City helpers (lines ~1884–1888)
- `cityName()`: add `'jh' ? '金华'` (before the final `'北京'`).
- `cityLogo()`: add `this.jhLogo`.
- `transitLabel()`: add `'打开任我行'`.
- `transitIcon()`: add `this.rwxIcon`.
- `splashImg()`: add `this.jhSplash`.

### 1l. `timetableData()` (lines ~1899–1901)
Add `if (this.city === 'jh') return this.jhTimetable;` (after the dl line).

### 1m. tt-note (line ~755)
No Jinhua span needed — the Jinhua timetable is REAL (not estimated).
Do not add an estimate note.

## 2. `web/build_offline.py`

### 2a. 任我行 icon (after the `dljt_b64` block, ~line 158)
```python
rwx_b64 = (BASE / "renwoxing-icon.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__RWX_ICON__\*/', lambda _: rwx_b64, html, "renwoxing icon")
```

### 2b. Jinhua data inline (after the Dalian block, ~line 224)
```python
# S. inline the Jinhua Rail Transit data (Jinyi East Line, 2 routes, 29 stations).
# Same pattern as Harbin/Dalian: precomputed stations/routes from the user's
# ink-wash map (see jinhua/NOTES.md); the logo is the official mark
# (Wikimedia); the splash is a placeholder built from the map image.
jh_stations = (BASE / "jinhua" / "stations.json").read_text(encoding="utf-8")
jh_routes = (BASE / "jinhua" / "routes.json").read_text(encoding="utf-8")
jh_map = (BASE / "jinhua" / "map.svg").read_text(encoding="utf-8")
jh_logo_b64 = (BASE / "jinhua" / "logo.b64").read_text(encoding="utf-8").strip()
jh_splash_b64 = (BASE / "jinhua" / "splash.b64").read_text(encoding="utf-8").strip()
assert "</script" not in jh_stations, "jh stations json must not contain </script"
assert "</script" not in jh_routes, "jh routes json must not contain </script"
assert "</script" not in jh_map, "jh map svg must not contain </script"
html = sub_once(r'/\*__JH_STATIONS__\*/\[\]', lambda _: jh_stations, html, "jh stations json")
html = sub_once(r'/\*__JH_ROUTES__\*/null', lambda _: jh_routes, html, "jh routes json")
html = sub_once(r'/\*__JH_MAP__\*/""', lambda _: _json.dumps(jh_map), html, "jh map svg")
html = sub_once(r'/\*__JH_LOGO__\*/', lambda _: jh_logo_b64, html, "jh logo")
html = sub_once(r'/\*__JH_SPLASH__\*/', lambda _: jh_splash_b64, html, "jh splash")
```

### 2c. Timetable inline (after the `dl_tt` block, ~line 232)
```python
jh_tt = (BASE / "timetable" / "jh.json").read_text(encoding="utf-8")
assert "</script" not in jh_tt, "jh timetable json must not contain </script"
html = sub_once(r'/\*__JH_TIMETABLE__\*/\{\}', lambda _: jh_tt, html, "jh timetable json")
```

## 3. `app/AppDelegate.swift`

### 3a. Theme colours (near `harbinRed` / `dalianBlue`, lines ~113–120)
```swift
// Jinhua brand dark red #D8273D (Wikipedia Template:金华轨道交通颜色,
// code JYD; 标志色：深红色). Darker #A81E30 for selected states/text.
let jinhuaRed = UIColor(red: 216.0 / 255.0, green: 39.0 / 255.0, blue: 61.0 / 255.0, alpha: 1)
let jinhuaRedDark = UIColor(red: 168.0 / 255.0, green: 30.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)
```

### 3b. Restore saved city (line ~155)
Add `"jh"` to `["bj", "sy", "sh", "hb", "dl"]`.

### 3c. Native splash (line ~301)
Add `case "jh": splashName = "SplashJH"` (after the dl case).

### 3d. Accent / search button / logo / pill name
- `accentColor()` (~line 393): `if currentCity == "jh" { return jinhuaRed }`.
- `accentDark()` (~line 403): `if currentCity == "jh" { return jinhuaRedDark }`.
- `searchButtonColor()` (~line 416): `if currentCity == "jh" { return jinhuaRed }`.
- `cityLogoImage()` (~line 426): `case "jh": name = "JinhuaLogo"`.
- `updateCityPill()` (~line 443): `case "jh": name = "金华"`.

### 3e. City menu (lines ~500–506)
Add a `jh` UIAction (`title: "金华"`, `pickCity("jh")`) and include it in
the `UIMenu` children (order: bj, sy, sh, hb, dl, jh).

### 3f. City sheet (lines ~523–527)
Add `sheet.addAction(UIAlertAction(title: currentCity == "jh" ? "✓ 金华" : "金华", style: .default) { [weak self] _ in self?.pickCity("jh") })`.

### 3g. `openTransitApp()` (line ~1268)
Add `case "jh": id = "6503238645"` and update the comment (add 任我行 6503238645 to the verified list).

### 3h. `cityChanged` handler (line ~1511) — KNOWN GAP, fix while here
The handler's accept list is still `["bj", "sy", "sh"]` — Harbin and Dalian
are missing too, so a web-initiated switch to hb/dl/jh is not mirrored
natively (cosmetic: native tint/pills lag until the next native action).
Change the list to `["bj", "sy", "sh", "hb", "dl", "jh"]`.

## 4. `build.sh`

After the Dalian splash line (~line 57):
```sh
# Jinhua splash (placeholder built from the map image, web/jinhua/splash.b64).
python3 -c "import base64; open('build/Payload/Metro.app/SplashJH.jpg','wb').write(base64.b64decode(open('web/jinhua/splash.b64').read()))"
```
After the DalianLogo line (~line 60):
```sh
python3 -c "import base64; open('build/Payload/Metro.app/JinhuaLogo.png','wb').write(base64.b64decode(open('web/jinhua/logo.b64').read()))"
```

## 5. Build / verify (after wiring)

1. Bump `app/Info.plist` CFBundleVersion to the new build number.
2. Push only sources (never `web/offline/index.html` — push-files rejects
   it with HTTP 413); trigger one run of **Build Metro IPA**.
3. Download and verify the IPA: `JH_STATIONS`/`JH_TIMETABLE` inlined,
   `SplashJH.jpg` + `JinhuaLogo.png` in the bundle, `CFBundleVersion`
   correct.
4. On-device checks: switch to 金华 — the map shows (not Beijing),
   金华站→明清宫 routes, fare ¥17, timetable shows real first/last
   (金华站往秦塘 06:25/22:00), transit row says 打开任我行, search button
   is dark red #D8273D, tab bar selected state is dark red.
5. Also verify the fare cross-checks (1i) and that switching back to
   Beijing still works (regression).

## Known caveats (from NOTES.md — do not "fix" silently)

- 29 operating stations, not the published "30" (that count includes the
  unbuilt 横店客运中心; "31" also counts the unbuilt 车辆段站).
- The map image predates the 横店高铁站 (2024-09-06) and 义乌高铁站
  (2026-07-01) openings — both are drawn but marked 未开通 on the image.
  Data is correct; the image marks are a cosmetic caveat.
- All 29 coordinates are chainage-interpolated (no machine-detectable
  station ticks on the ink-wash map); validated by numbered overlay.
- Splash is a placeholder from the map image; replace if the user sends
  a dedicated Jinhua splash.
- Zoom will blur (JPEG-in-SVG, same as the other raster cities).
