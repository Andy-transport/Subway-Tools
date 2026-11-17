# Jinhua Rail Transit (金华轨道交通) — NOTES (web/jinhua/)

Jinhua support for Subway motion, 6th city (`jh`). One line, the Jinyi East
Line (金义东线), **29 unique operating stations** (see the 29-vs-30 note below).

## Network (verified 2026-11-16, user map + Wikipedia line tables)

The Jinyi East Line is a Y-shaped line with the junction at 秦塘. It is
operated as **two separate routes** (独立交路) that meet at 秦塘 with a
same-platform transfer (双岛四线同站台换乘). A through express (大站快车)
also runs 金华站—明清宫.

| Key | Line | Colour | Stations | Termini |
|-----|------|--------|----------|---------|
| JY | 金义线 | dark red `D8273D` | 16 | 金华站 → 秦塘 |
| YD | 义东线 | dark red `D8273D` | 14 | 义乌高铁站 → 明清宫 |

Line entries total 30; 秦塘 appears in both lines, so 30 − 1 = **29 unique
stations**. 秦塘 is the only interchange (JY + YD).

金义线 (JY), west → east: 金华站、双溪西路、八一南街、万达广场、大堰河街、
轨道大厦、金华南站、塘雅、综保区、新区、东华街、义亭、官塘、稠江、绣湖、
秦塘.

义东线 (YD), north → south: 义乌高铁站、凌云、春晗、秦塘、国际商贸城、
浙医四院、江东、木雕城、歌山路、人民路、会展中心、体育馆、横店高铁站、
明清宫.

**Excluded — NOT operating**: 车辆段站 (金义线, 暂未开通, between 塘雅 and
综保区); 横店客运中心站 (义东线, 缓建, beyond 明清宫). Neither is on the
user's map and neither is in stations.json.

**29 vs published 30**: Wikipedia's infobox says 车站数目 30 and the article
says 共设站31座 (秦塘站计为2座). Both counts include the unbuilt
横店客运中心 (and 31 also counts the unbuilt 车辆段站). Operating stations
are 29: 金义线 16 + 义东线 14 (excl. 横店客运中心) − 1 shared 秦塘 = 29.
Do NOT silently claim 30.

## Station names — map labels vs official names

The user's map is a decorative ink-wash image (MetroMan 地铁通 style). Two
labels on it use shortened names; the data uses the official names:
- Map "义乌站" = official **义乌高铁站** (opened 2026-07-01; the map marks
  it 未开通, which is outdated — see below).
- Map "横店站" = official **横店高铁站** (opened 2024-09-06; the map marks
  it 未开通, also outdated).
- Map "桐江"-looking label between 官塘 and 绣湖 is **稠江** (confirmed by
  the Wikipedia station table and RDT; the calligraphy is ambiguous).

The map also labels districts (婺城、金东、义乌、东阳) in red boxes — those
are NOT stations.

**Map age**: the map predates the 横店高铁站 (2024-09-06) and
义乌高铁站 (2026-07-01) openings — both are drawn but marked 未开通 on the
image. Both are operating now and are included as operating stations. The
map is used as-is (JPEG-in-SVG); the 未开通 marks remain visible on the
image, which is a known cosmetic caveat, not a data error.

## Station coordinates (map 1206×827, user's image)

The map is a schematic ink-wash drawing, not a geographic map. Station dots
are thin white ticks on the red band and are NOT reliably machine-detectable
(they are 1–2 px, anti-aliased, and the image has pink mountain washes that
defeat colour thresholding). Method used instead:
- Traced the red band centreline from the saturated-red mask (median y per
  x-column): the main diagonal 金华站 → 秦塘 → 明清宫, including the U-bend
  at the 金华站 end (lowest point ~(180,656)).
- The 义乌 arm (秦塘 → 义乌高铁站) is a paler pink; traced it with a loose
  pink-red mask and an ASCII density map. Its visible terminus is ~(586,338),
  NOT (525,330) as first assumed (that point is white background).
- Placed each station along its arm by **real chainage** (km, from the
  Wikipedia station tables), interpolating along the centreline arc length.
  This matches the real inter-station distances, which is what the
  distance-based fare needs.
- Validated with a numbered overlay (blue dots on the map): all 29 dots land
  on the red/pink band, in the correct order, next to their labels.

Chainage (km) used — 金义段: 金华站 0.125, 双溪西路 2.465, 八一南街 4.122,
万达广场 6.378, 大堰河街 9.249, 轨道大厦 11.054, 金华南站 14.318,
塘雅 24.291, 综保区 29.338, 新区 31.551, 东华街 33.642, 义亭 42.591,
官塘 48.411, 稠江 50.544, 绣湖 54.391, 秦塘 58.022. 义东段:
义乌高铁站 0.412, 凌云 3.889, 春晗 5.956, 秦塘 8.239, 国际商贸城 9.877,
浙医四院 11.896, 江东 15.577, 木雕城 20.393, 歌山路 23.708,
人民路 26.205, 会展中心 28.327, 体育馆 30.715, 横店高铁站 37.000,
明清宫 44.384.

**px/km (for the fare model)**: JY arm 11.90 (689.2 px / 57.90 km),
YD main arm (秦塘→明清宫) 13.06 (471.9 px / 36.15 km),
YD 义乌 arm (秦塘→义乌高铁站) 19.06 (149.2 px / 7.83 km — the short arm is
drawn stretched, ~1.5× the main-arm scale). See WIRING.md for how to use
these in `shScaleFor` (a single YD value of 13.06 is acceptable: the fare
error from the stretched arm is ≤ ¥1, usually ¥0; a midpoint test gives
exactness).

**All 29 stations are chainage-interpolated** (no tick was cleanly
machine-detected). The overlay check is the validation; no station was
placed by eye alone.

## Map

`map.svg` is a JPEG-in-SVG wrapper (the user's map JPEG embedded), the same
approach as Shanghai/Harbin/Dalian. There is no potrace/autotrace/vtracer on
this machine, so no true vector trace — **zoom sharpness will NOT materially
improve** over the JPEG (same caveat as the other raster cities).

## Fare (verified, Wikipedia 票务 + 金华市发改委)

Distance-based, by ride distance:
- ¥2 for the first 8 km (含 8 km).
- 8–28 km (含 28 km): +¥1 per 4 km.
- 28–64 km (含 64 km): +¥1 per 6 km.
- 64 km and above: +¥1 per 8 km.
- (Ceil each band's increment, as in the other cities.)

Cross-checks (published): 金华站—秦塘 ¥12; 金华站—明清宫 ¥17;
金华站—体育馆 ¥16; 凌云—明清宫 ¥10. The app should reproduce these from
the chainage/px distances (see WIRING.md).

## Timetable (REAL, not estimated)

`web/timetable/jh.json` is transcribed from the official 金华轨道交通
first/last-train images (via 金华本地宝, images dated 2026-04-30):
- 金义线各车站首末班车发车时刻表
- 义东线各车站首末班车发车时刻表

Operating hours roughly **05:58–23:37** (first departure 05:58 秦塘→金华,
last arrival 23:37 明清宫). Per-station first/last are the published values
for both directions; termini have null for the direction toward themselves
(same convention as Harbin/Dalian).

Notes from the source tables:
- 金华站 22:00 departures continue through 秦塘 to 明清宫 (skipping
  义乌高铁站/凌云/春晗; no change at 秦塘).
- 明清宫站 22:00 departures continue through 秦塘 to 金华站 (same skip).
- 秦塘 (金义) 22:59 departure continues to 明清宫.
- Some first trains originate at intermediate stations (marked 发 in the
  source): 金华南站 06:30, 综保区 06:32, 东华街 06:30 (toward 秦塘);
  浙医四院 06:30 (toward 明清宫); 会展中心 06:30 (toward 义乌高铁站).
- One source inconsistency, kept as published: 金义线往金华方向末班车 at
  双溪西路 is 23:35 but at 金华站 is 23:28 (到) — the 金华站 value is an
  arrival and does not enter the data (金华站 toward-itself is null), so it
  has no effect on the app.
- Timetable refresh: the source images are dated 2026-04-30. A later
  adjustment was reported 2025-09-28 (金华站末班 22:00, 明清宫末班 22:40,
  凌云末班 22:30) — the 2026-04-30 images already reflect those times
  (凌云往明清宫末班 is 22:33 in the image vs 22:30 in the 2025 notice;
  use the image value). Re-check if the operator publishes a new table.

## Logo / splash / theme / transit app

- Logo: official Jinhua Rail Transit mark (red swoosh + 金华轨道交通 /
  JINHUA RAIL TRANSIT lockup) from Wikimedia
  (`金华轨道交通.png`, 286×64). The red swoosh graphic is cropped to a
  120×120 square (`logo.b64` / `logo.png`); the wide lockup is NOT used
  (the app renders the logo in a small circle). Median swoosh red #DA251D.
- Splash: the user did NOT send a Jinhua splash. `splash.b64` is a
  **placeholder built from the map image**: a 1170×2532 white portrait canvas
  with the map image scaled to full width and centred vertically (the map's
  white background blends with the canvas). It is NOT a designed splash.
  If the user sends a dedicated Jinhua portrait splash, replace
  `splash.b64` with it (same 1170×2532 pattern as Harbin/Dalian).
- Theme: Jinhua Rail Transit line colour **#D8273D** (Wikipedia
  Template:金华轨道交通颜色, code JYD; 标志色：深红色). The map's red band
  is the same colour family. Darker variant for selected states/text:
  **#A81E30**. Used for the web `.jh-theme` CSS and the native
  accent/search-button colour. The user can change it.
- Transit jump: **任我行** (Renwoxing), the official Jinhua Rail Transit
  app (formerly 金轨智行), by 金华轨道数智科技有限公司. App Store id
  **6503238645** ("任我行-吃行游乐，任我畅行", bundle
  com.bwton.msx.jinhuametro). No confirmed URL scheme → App Store link,
  same as Harbin/Dalian. Icon `web/renwoxing-icon.b64` is the App Store
  artwork (512 px) resized to 120×120.

## Sources

- Station lists, chainage, opening dates, fare: zh.wikipedia.org
  金华轨道交通金义东线 (crawled 2026-11-09) and 金华轨道交通.
- First/last times: 金华轨道交通 official timetable images via
  金华本地宝 m.jh.bendibao.com/traffic/23004.shtm (images dated
  2026-04-30).
- Line colour: zh.wikipedia.org Template:金华轨道交通颜色 (JYD → #d8273d).
- Logo: Wikimedia `金华轨道交通.png`.
- 任我行 App Store id: iTunes Search API (term 任我行, CN), trackId
  6503238645, seller Jinhua track digital intelligence Technology Co., LTD.
- Map image: user's photo
  `133EB74F-A1CF-4118-97F5-6E3C3DCB39C4-photo-A0C66864-159E-422B-A45A-E3F501292466.jpg`
  (1206×827, MetroMan 地铁通 ink-wash style).
