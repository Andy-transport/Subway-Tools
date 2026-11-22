# Upcoming-city metro logos — manifest

Scope: the 46 not-yet-supported cities in `soonCityList()` in `web/template.html`
(the 11 supported cities and Qingdao are handled elsewhere and excluded here).

Logos are official Wikimedia files used as-is (API thumbnails, `iiurlwidth=480`;
no redrawing or alteration). Every saved logo was visually verified against the
downloaded image before being copied here.

**Status of this run (2026-11-22, third pass):** STOPPED EARLY — HTTP 429 again.
The API (commons.wikimedia.org / zh.wikipedia.org) answered normally and all 8
previously located candidates were CONFIRMED present as zh.wikipedia local
files (exact URLs now recorded below). But the first image download from
upload.wikimedia.org returned **HTTP 429**, so per the hard rate-limit rule all
Wikimedia requests were stopped immediately — no retries, no endpoint
switching. Nothing was downloaded or visually verified in this pass, and the
24 unsearched cities were not searched. 天津's logo currency is still
unconfirmed. A later pass (after the rate limit clears) can go straight to
downloading the 8 confirmed files below.

## Saved & verified (13)

| City | File | Wikimedia source file |
|---|---|---|
| 天津 Tianjin | `tianjin.png` | File:Tianjin Metro Old Logo.svg — ⚠️ source file is named "Old Logo"; it is the red Tianjin Metro roundel shown in the 天津地铁 article, but whether it is the *current* logo could not be re-checked (rate limit). Parent: confirm before shipping. |
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
| 徐州 Xuzhou | `xuzhou.png` | File:Xuzhou Metro New Logo with char.svg |

## Located on zh.wikipedia — confirmed present, download blocked by HTTP 429 (8)

Confirmed via the zh.wikipedia API on 2026-11-22 (third pass); still NOT
downloaded and NOT visually verified — download and verify in a later run.

| City | zh.wikipedia file | File URL (upload.wikimedia.org) |
|---|---|---|
| 郑州 Zhengzhou | File:Zhengzhou Metro Logo (no text).png (233×280) | https://upload.wikimedia.org/wikipedia/zh/a/a3/Zhengzhou_Metro_Logo_%28no_text%29.png |
| 兰州 Lanzhou | File:Lanzhou Rail Transit Logo.png (120×118) | https://upload.wikimedia.org/wikipedia/zh/4/40/Lanzhou_Rail_Transit_Logo.png |
| 合肥 Hefei | File:Hefei Metro Logo.png (301×338) | https://upload.wikimedia.org/wikipedia/zh/8/88/Hefei_Metro_Logo.png |
| 乌鲁木齐 Ürümqi | File:URUMQI METRO LOGO.png (300×188) | https://upload.wikimedia.org/wikipedia/zh/0/0d/URUMQI_METRO_LOGO.png |
| 呼和浩特 Hohhot | File:Hohhot Metro Logo v1.png (259×52) | https://upload.wikimedia.org/wikipedia/zh/7/7b/Hohhot_Metro_Logo_v1.png |
| 太原 Taiyuan | File:Taiyuan metro logo.png (316×315) | https://upload.wikimedia.org/wikipedia/zh/6/64/Taiyuan_metro_logo.png |
| 芜湖 Wuhu | File:Wuhu RT Logo.png (277×69) | https://upload.wikimedia.org/wikipedia/zh/4/48/Wuhu_RT_Logo.png |
| 滁州 Chuzhou | File:滁州轨道logo.jpg (316×316, JPG → convert to PNG like Nanchang) | https://upload.wikimedia.org/wikipedia/zh/3/3c/%E6%BB%81%E5%B7%9E%E8%BD%A8%E9%81%93logo.jpg |

## Not yet found — search not completed (24)

The city's zh.wikipedia article image list contained no logo file, and the
follow-up Commons/zh file search could not be run because of the HTTP 429
hard stop. These are **not** confirmed missing from Wikimedia — they are
simply unsearched. Do not treat as "no logo exists".
(石家庄 in the list below is stale — it is now a supported city and not in
`soonCityList()`. 雄安 is not listed: it has no metro logo and keeps the
grey 'M' by design.)

武汉 Wuhan · 苏州 Suzhou · 昆明 Kunming · 佛山 Foshan · 宁波 Ningbo ·
淮安 Huai'an (tram) · 东莞 Dongguan · 贵阳 Guiyang ·
厦门 Xiamen · 天水 Tianshui (tram) · 三亚 Sanya (tram) · 株洲 Zhuzhou (ART) ·
宜宾 Yibin (ART) · 洛阳 Luoyang · 嘉兴 Jiaxing (tram) · 绍兴 Shaoxing ·
文山州 Wenshan (tram) · 南平 Nanping (Wuyi tram) · 南通 Nantong ·
台州 Taizhou · 黄石 Huangshi (tram) · 盐城 Yancheng · 红河州 Honghe (tram) ·
许昌 Xuchang (Zhengxu line)
