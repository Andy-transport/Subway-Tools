# Upcoming-city metro logos — manifest

Scope: the 46 not-yet-supported cities in `soonCityList()` in `web/template.html`
(the 11 supported cities and Qingdao are handled elsewhere and excluded here).
石家庄 Shijiazhuang is also excluded — it is now a supported city and its logo
is handled with the supported set.

Logos are official Wikimedia files used as-is (API thumbnails, `iiurlwidth=480`;
no redrawing or alteration). Every saved logo was visually verified against the
downloaded image before being copied here.

**Status of this run (2026-11-21, second pass):** STOPPED EARLY — HTTP 429.
The 8 known candidates were located (see below), but every download from
upload.wikimedia.org returned **HTTP 429 (rate limit)**. Per the hard
rate-limit rule, all Wikimedia requests were stopped immediately — no retries,
no endpoint-switching. Nothing new was downloaded or verified in this pass.
天津 could not be re-checked, and the unsearched cities were not searched.
A later pass (after the rate limit clears) should resume from the
"Located — download blocked" section: the exact file locations are now known.

## Saved & verified (13 files on disk; 12 with .b64)

| City | File | Wikimedia source file |
|---|---|---|
| 天津 Tianjin | `tianjin.png` (no .b64 yet) | File:Tianjin Metro Old Logo.svg — ⚠️ source file is named "Old Logo"; it is the red Tianjin Metro roundel shown in the 天津地铁 article, but whether it is the *current* logo could not be re-checked (rate limit, both passes). Parent: confirm before shipping. |
| 广州 Guangzhou | `guangzhou.png` | File:Guangzhou Metro logo.svg |
| 南京 Nanjing | `nanjing.png` | File:Nanjing Metro Logo.svg |
| 西安 Xi'an | `xian.png` | File:Xi'an Metro Logo.png |
| 杭州 Hangzhou | `hangzhou.png` | File:Hangzhou Metro Logo.png |
| 长沙 Changsha | `changsha.png` | File:Changsha Metro logo.svg |
| 无锡 Wuxi | `wuxi.png` | File:Wuxi Metro Logo.png |
| 南昌 Nanchang | `nanchang.png` | File:Nanchang Metro logo.jpg (JPG converted to PNG, artwork unchanged) |
| 福州 Fuzhou | `fuzhou.png` | File:Fuzhou Metro logo.png |
| 南宁 Nanning | `nanning.png` | File:Nanning Rail Transit Logo.png |
| 温州 Wenzhou | `wenzhou.png` | File:Wenzhou Rail Transit Logo.svg |
| 济南 Jinan | `jinan.png` | File:JinanMetro Logo.svg |
| 徐州 Xuzhou | `xuzhou.png` | File:Xu
...[truncated 2705 chars]
## 26E109 — cut from the user's logo-collage photo (18 cities)

Source: the user's own collage photo of city metro logos (a grid,
each glyph with its city name printed underneath). Method: per-cell
crop on the measured glyph row bands, white background flood-filled
to transparency, artwork untouched, no city-name text included.
Every cutout was visually verified against the collage on a contact
sheet (correct city, complete glyph, no clipped edges). Display
stays grey (`.more-soon-logo` grayscale filter, unchanged). All 18
are wired in `build_offline.py` `_SOON_LOGO_FILES`.

| City | File | Note |
|---|---|---|
| 天津 Tianjin | `tianjin.png` | Collage cut — the same red roundel as the Wikimedia "Old Logo" file in the table above; supersedes the earlier held-back no-.b64 copy |
| 太原 Taiyuan | `taiyuan.png` | Collage cut |
| 呼和浩特 Hohhot | `huhehaote.png` | Collage cut |
| 苏州 Suzhou | `suzhou.png` | Collage cut |
| 南通 Nantong | `nantong.png` | Collage cut |
| 宁波 Ningbo | `ningbo.png` | Collage cut |
| 绍兴 Shaoxing | `shaoxing.png` | Collage cut |
| 合肥 Hefei | `hefei.png` | Collage cut |
| 厦门 Xiamen | `xiamen.png` | Collage cut |
| 郑州 Zhengzhou | `zhengzhou.png` | Collage cut |
| 洛阳 Luoyang | `luoyang.png` | Collage cut |
| 武汉 Wuhan | `wuhan.png` | Collage cut |
| 佛山 Foshan | `foshan.png` | Collage cut |
| 东莞 Dongguan | `dongguan.png` | Collage cut |
| 贵阳 Guiyang | `guiyang.png` | Collage cut |
| 昆明 Kunming | `kunming.png` | Collage cut |
| 兰州 Lanzhou | `lanzhou.png` | Collage cut |
| 乌鲁木齐 Ürümqi | `wulumuqi.png` | Collage cut |

## Still missing — keep the grey M (not in the collage; do not fabricate)

淮安 Huai'an · 天水 Tianshui · 三亚 Sanya · 株洲 Zhuzhou · 宜宾 Yibin ·
嘉兴 Jiaxing · 文山州 Wenshanzhou · 芜湖 Wuhu · 南平 Nanping · 台州 Taizhou ·
黄石 Huangshi · 盐城 Yancheng · 红河州 Honghezhou · 滁州 Chuzhou ·
许昌 Xuchang.

## User-provided (2026-11-22)

| City | File | Note |
|---|---|---|
| 雄安 Xiong'an | `xiongan.png` | 用户提供图片 2026-11-22 — the user's own photo of the green Xiong'an mark; white background and inner negative space converted to transparency, green artwork untouched, not redrawn. Xiong'an remains a greyed, non-tappable placeholder city (no search/routing); only the icon changed from the grey M to this mark, shown greyed like the others. Wired in `build_offline.py` `_SOON_LOGO_FILES`. |
