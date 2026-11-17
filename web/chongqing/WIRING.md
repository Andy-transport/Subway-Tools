# Wiring Chongqing (`cq`) into the app — DO NOT do this until build 66
# (Jinhua wiring) is pushed

This file lists the exact edits to wire the prepared Chongqing data
(`web/chongqing/`, `web/timetable/cq.json`, `web/yuchangxing-icon.b64`) into
the app as city `'cq'`. It follows the Jinhua (build 66) pattern exactly.
**Wait until the Jinhua wiring is pushed and its AppDelegate.swift /
template.html changes are in** — Jinhua is editing both files (see
`web/jinhua/WIRING.md`). Rebase these edits on the post-Jinhua head; line
numbers below are from the pre-Jinhua files and WILL shift. Chongqing is
the 7th city; the 58-city directory (build 65) lists it greyed as
"即将支持" — make it tappable when wiring.

Files already prepared (do not re-create):
- `web/chongqing/stations.json` — 282 stations {n, py, ini, x, y}
- `web/chongqing/routes.json` — 16 line keys (0,1,2,3,3B,4,5,6,6B,6C,9,10,
  15,18,JT,BT), 330 edges; Loop (0) is a closed ring (closing edge
  华龙→重庆西站 included, Shanghai-L4 pattern)
- `web/chongqing/map.svg` — JPEG-in-SVG wrapper, viewBox 0 0 1206 1111,
  id="svg8"
- `web/chongqing/logo.b64` — CRT green logo mark, cropped from the map
- `web/chongqing/splash.b64` — REAL user splash, edited (TRACK LAYOUT
  LOOKUP removed; see NOTES.md)
- `web/timetable/cq.json` — 282 stations, 345 station-line entries
  (last trains REAL for Loop/1/2/3/4/5/6/9/10/18; first trains ESTIMATED;
  JT REAL; L15/BT ESTIMATED — see NOTES.md)
- `web/yuchangxing-icon.b64` — 渝畅行 app icon, 120×120 PNG (App Store
  artwork, id 1491110313)
- `web/chongqing/NOTES.md` — full data documentation

## 1. `web/template.html`

### 1a. Global placeholders (near lines 22–47, next to the JH ones)
```js
window.CQ_STATIONS = /*__CQ_STATIONS__*/[];
window.CQ_ROUTES = /*__CQ_ROUTES__*/null;
window.CQ_MAP = /*__CQ_MAP__*/"";
window.CQ_LOGO = "data:image/png;base64,/*__CQ_LOGO__*/";
window.YCX_ICON = "data:image/png;base64,/*__YCX_ICON__*/";
window.CQ_SPLASH = "data:image/png;base64,/*__CQ_SPLASH__*/";
window.CQ_TIMETABLE = /*__CQ_TIMETABLE__*/{};
```

### 1b. Root div theme class (line ~646)
Add `'cq-theme': city === 'cq'` to the `:class` binding (after `'jh-theme'`).

### 1c. CSS — add after the `.jh-theme` rules
```css
/* Chongqing theme: CRT green #0A814B (logo green; median #0F7F4C).
   Darker #076138 for text accents. */
.cq-theme #brandChip, .cq-theme #searchPill { color: #076138; }
.cq-theme .tr-search { background: linear-gradient(180deg, rgba(10, 129, 75, 0.9), rgba(7, 97, 56, 0.9)) !important; }
.cq-theme .tr-pref button.on { background: #0a814b; }
.cq-theme .sp-row .sp-line { background: #0a814b; }
.cq-theme .tr-city { color: #076138 !important; }
.cq-theme .tr-swap { color: #076138; border-color: rgba(10,129,75,0.35); }
.cq-theme .tr-tabs button { color: #076138; }
.cq-theme .tr-tabs button.on { background: #0a814b; color: #fff; }
```

### 1d. `data()` — city validator (line ~1024)
Add `'cq'` to the allowed list (after `'jh'`).

### 1e. `data()` — city data fields (after the `jh*` fields)
```js
cqStations: (window.CQ_STATIONS || []),
cqRoutes: (window.CQ_ROUTES || null),
cqLogo: (window.CQ_LOGO || ''),
cqMap: (window.CQ_MAP || ''),
ycxIcon: (window.YCX_ICON || ''),
cqSplash: (window.CQ_SPLASH || ''),
cqTimetable: (window.CQ_TIMETABLE || {}),
```

### 1f. `switchCity()` guard + branch (lines ~1182–1200)
Guard (after the jh guard):
```js
if (c === 'cq' && (!this.cqStations.length || !this.cqMap)) return;
```
Branch (after the jh branch, before the final `else`):
```js
} else if (c === 'cq') {
    this.stations = this.cqStations;
    this.routes = this.cqRoutes;
    this.curr = { svgUrl: "", svgDom: this.cqMap, pdfUrl: "", success: true, json: null, verName: "CQ", verInfo: "{ 重庆轨道交通 , 2026-11 , 14条线 282站 }", showCmitInfo: false, cmitFixed: "", cmitVar: "" };
```

### 1g. Mount force-switch (line ~2034)
Add `'cq'` to the list (after `'jh'`).

### 1h. `shScaleFor()` — Chongqing px/km (after the `jh` branch)
```js
if (this.city === 'cq') {
    // Chongqing px/km = pixel path length / real line length (see
    // chongqing/NOTES.md). The map is schematic; scale varies by line
    // (Loop 29.8, L10 28.9, L9 27.0, L3 23.6, L2 22.2, L4 20.2,
    // L15 20.1, L5 19.6, L1 19.3, L6 16.8, BT 9.0 — far west compressed).
    // Branches share the parent value. L18/JT use the network median 20
    // (real lengths not confirmed). Fare error from scale variation is
    // typically ±¥1.
    const pxkm = { '0': 29.76, '1': 19.34, '2': 22.18, '3': 23.63,
        '3B': 23.63, '4': 20.21, '5': 19.60, '6': 16.80, '6B': 16.80,
        '6C': 16.80, '9': 26.99, '10': 28.90, '15': 20.11, '18': 20,
        'JT': 20, 'BT': 8.97 };
    return pxkm[lineKey] || 20;
}
```

### 1i. Fare — Chongqing block (after the `jh` fare block)
Same shape as the Harbin/Dalian/Jinhua blocks: sum `segKm` over
`r.segments`, then apply the 2025 bands (verified, 渝发改规范〔2025〕1号,
effective 2025-07-30; the pre-2025 table with a ¥10 cap is SUPERSEDED):
- ≤ 4 km → ¥2
- 4–8 km → ¥3
- 8–12 km → ¥4
- 12–17 km → ¥5
- 17–23 km → ¥6
- 23–30 km → ¥7
- 30–40 km → ¥8
- 40–55 km → ¥9
- 55 km+ → 9 + ceil((km − 55) / 20)

Cross-checks the app must reproduce:
井口—两江影视城 (15号线 full length, ~48 km) ¥9 ·
longest trip 88 km ¥11.

NOTE: 江跳线/璧铜线 have SEPARATE fares (JT: start ¥2, cap ¥9 per the
2025-11-01 notice; BT: 0.4元/km, start ¥2, cap ¥15, added on top of the
metro fare). If a route uses JT or BT, the metro fare above is NOT the
full price — flag it in the UI (or show the metro fare + a note). Do NOT
present an unverified JT bracket table.

### 1j. Transit app id (line ~1630, `openTransitApp()`)
Add the `'cq'` case: `... (this.city === 'jh' ? '6503238645' : (this.city === 'cq' ? '1491110313' : '1071038870'))`. (渝畅行, App Store id 1491110313.)

### 1k. City helpers (lines ~1884–1888)
- `cityName()`: add `'cq' ? '重庆'` (before the final `'北京'`).
- `cityLogo()`: add `this.cqLogo`.
- `transitLabel()`: add `'打开渝畅行'`.
- `transitIcon()`: add `this.ycxIcon`.
- `splashImg()`: add `this.cqSplash`.

### 1l. `timetableData()` (lines ~1899–1901)
Add `if (this.city === 'cq') return this.cqTimetable;` (after the jh line).

### 1m. tt-note (line ~755)
Add a `tt.note.cq` span (like `tt.note.hb`/`tt.note.dl`): the Chongqing
timetable mixes REAL last trains with ESTIMATED first trains (first trains
on Loop/1/2/3/4/5/6/9/10/18 are estimated from the last-train travel
pattern; L15/BT per-station times are estimated from line hours; JT times
are real). Suggested text (3 languages, via window.I18N):
"首班车时间为估算（按末班车行车时间推算），15号线/璧铜线各站时间为估算；
末班车及江跳线时间为官方时刻表。" / Traditional + English equivalents.

### 1n. 58-city directory (build 65)
Chongqing is in the 58-city directory as greyed "即将支持". Make it
tappable (like the 5 supported cities) and add its logo row. (金华 is
also greyed — wire it per its own WIRING.md; do not conflate the two.)

## 2. `web/build_offline.py`

### 2a. 渝畅行 icon (after the `rwx_b64` block)
```python
ycx_b64 = (BASE / "yuchangxing-icon.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__YCX_ICON__\*/', lambda _: ycx_b64, html, "yuchangxing icon")
```

### 2b. Chongqing data inline (after the Jinhua block)
```python
# S. inline the Chongqing Rail Transit data (14 lines, 282 stations).
# Same pattern as Jinhua: precomputed stations/routes from the user's
# system-plan map (see chongqing/NOTES.md); the logo is cropped from the
# map; the splash is the user's real image, edited (see NOTES.md).
cq_stations = (BASE / "chongqing" / "stations.json").read_text(encoding="utf-8")
cq_routes = (BASE / "chongqing" / "routes.json").read_text(encoding="utf-8")
cq_map = (BASE / "chongqing" / "map.svg").read_text(encoding="utf-8")
cq_logo_b64 = (BASE / "chongqing" / "logo.b64").read_text(encoding="utf-8").strip()
cq_splash_b64 = (BASE / "chongqing" / "splash.b64").read_text(encoding="utf-8").strip()
assert "</script" not in cq_stations, "cq stations json must not contain </script"
assert "</script" not in cq_routes, "cq routes json must not contain </script"
assert "</script" not in cq_map, "cq map svg must not contain </script"
html = sub_once(r'/\*__CQ_STATIONS__\*/\[\]', lambda _: cq_stations, html, "cq stations json")
html = sub_once(r'/\*__CQ_ROUTES__\*/null', lambda _: cq_routes, html, "cq routes json")
html = sub_once(r'/\*__CQ_MAP__\*/""', lambda _: _json.dumps(cq_map), html, "cq map svg")
html = sub_once(r'/\*__CQ_LOGO__\*/', lambda _: cq_logo_b64, html, "cq logo")
html = sub_once(r'/\*__CQ_SPLASH__\*/', lambda _: cq_splash_b64, html, "cq splash")
```

### 2c. Timetable inline (after the `jh_tt` block)
```python
cq_tt = (BASE / "timetable" / "cq.json").read_text(encoding="utf-8")
assert "</script" not in cq_tt, "cq timetable json must not contain </script"
html = sub_once(r'/\*__CQ_TIMETABLE__\*/\{\}', lambda _: cq_tt, html, "cq timetable json")
```

## 3. `app/AppDelegate.swift`

### 3a. Theme colours (near `jinhuaRed`, lines ~113–120)
```swift
// Chongqing CRT green #0A814B (logo green; median #0F7F4C).
// Darker #076138 for selected states/text.
let chongqingGreen = UIColor(red: 10.0 / 255.0, green: 129.0 / 255.0, blue: 75.0 / 255.0, alpha: 1)
let chongqingGreenDark = UIColor(red: 7.0 / 255.0, green: 97.0 / 255.0, blue: 56.0 / 255.0, alpha: 1)
```

### 3b. Restore saved city (line ~155)
Add `"cq"` to the list (after `"jh"`).

### 3c. Native splash (line ~301)
Add `case "cq": splashName = "SplashCQ"` (after the jh case).

### 3d. Accent / search button / logo / pill name
- `accentColor()` (~line 393): `if currentCity == "cq" { return chongqingGreen }`.
- `accentDark()` (~line 403): `if currentCity == "cq" { return chongqingGreenDark }`.
- `searchButtonColor()` (~line 416): `if currentCity == "cq" { return chongqingGreen }`.
- `cityLogoImage()` (~line 426): `case "cq": name = "ChongqingLogo"`.
- `updateCityPill()` (~line 443): `case "cq": name = "重庆"`.

### 3e. City menu (lines ~500–506)
Add a `cq` UIAction (`title: "重庆"`, `pickCity("cq")`) and include it in
the `UIMenu` children (order: bj, sy, sh, hb, dl, jh, cq).

### 3f. City sheet (lines ~523–527)
Add `sheet.addAction(UIAlertAction(title: currentCity == "cq" ? "✓ 重庆" : "重庆", style: .default) { [weak self] _ in self?.pickCity("cq") })`.

### 3g. `openTransitApp()` (line ~1268)
Add `case "cq": id = "1491110313"` and update the comment (add 渝畅行
1491110313 to the verified list).

### 3h. `cityChanged` handler (line ~1511)
Extend the accept list to `["bj", "sy", "sh", "hb", "dl", "jh", "cq"]`.
(This is the KNOWN GAP from the Jinhua WIRING.md — Harbin/Dalian/Jinhua
mirroring is also missing. Fix it while wiring Chongqing; do not leave
Chongqing unmirrored.)

## 4. `build.sh`

After the Jinhua splash line:
```sh
# Chongqing splash (real user image, edited — TRACK LAYOUT LOOKUP removed).
python3 -c "import base64; open('build/Payload/Metro.app/SplashCQ.jpg','wb').write(base64.b64decode(open('web/chongqing/splash.b64').read()))"
```
After the JinhuaLogo line:
```sh
python3 -c "import base64; open('build/Payload/Metro.app/ChongqingLogo.png','wb').write(base64.b64decode(open('web/chongqing/logo.b64').read()))"
```

## 5. Build / verify (after wiring)

1. Bump `app/Info.plist` CFBundleVersion to the new build number.
2. Push only sources (never `web/offline/index.html` — push-files rejects
   it with HTTP 413); trigger one run of **Build Metro IPA**.
3. Download and verify the IPA: `CQ_STATIONS`/`CQ_TIMETABLE` inlined,
   `SplashCQ.jpg` + `ChongqingLogo.png` in the bundle, `CFBundleVersion`
   correct.
4. On-device checks: switch to 重庆 — the map shows (not Beijing),
   沙坪坝→观音桥 routes, fare per the 2025 bands (井口—两江影视城 ¥9),
   timetable shows real last trains (e.g. 朝天门往璧山末班 00:00) and the
   estimated-first note, transit row says 打开渝畅行, search button is CRT
   green #0A814B, tab bar selected state is CRT green, Loop routes as a
   closed ring (二郎→华龙→重庆西站 works), 南坪 is searchable on 3号线
   only (NOT on 10号线）, 几江/鼎山/顺水寺公园/新桥/邮轮母港 are NOT
   searchable.
5. Also verify the fare cross-checks (1i) and that switching back to
   Beijing still works (regression).

## Known caveats (from NOTES.md — do not "fix" silently)

- 282 operating stations (not a published "300+" — the network has 14
  operating line keys; unopened lines/stations are excluded by the user's
  rule).
- 重庆理工大学 coordinate is interpolated (map omits its dot); 滩子口 is
  provisional; 渝北广场 is a judgment call. See NOTES.md.
- Loop timetable uses wayschina last trains (official cqmetro.cn static
  table could not be re-fetched); first trains are estimated.
- L15/BT per-station times are estimated from line hours (~2 min/stop).
- JT/BT have separate fares — the metro fare is not the full price on
  those lines.
- Zoom will blur (JPEG-in-SVG, same as the other raster cities).
- No lat/lng — location + nearby stations shows "即将上线".
