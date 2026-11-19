# Upcoming-city metro logos — manifest

Scope: the 46 not-yet-supported cities in `soonCityList()` in `web/template.html`
(the 11 supported cities and Qingdao are handled elsewhere and excluded here).

Logos are official Wikimedia files used as-is (API thumbnails, `iiurlwidth=480`;
no redrawing or alteration). Every saved logo was visually verified against the
downloaded image before being copied here.

**Status of this run:** sourcing was cut short when the Wikimedia API returned
HTTP 429 (rate limit) partway through the downloads. Per policy that is a hard
stop — the remaining cities below were NOT retried in this run and still need a
later pass.

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

## Candidate found in the city's article, download blocked by HTTP 429 (8)

Not downloaded and NOT visually verified yet — retry in a later run.

| City | Candidate Wikimedia file |
|---|---|
| 郑州 Zhengzhou | File:Zhengzhou Metro Logo (no text).png |
| 兰州 Lanzhou | File:Lanzhou Rail Transit Logo.png |
| 合肥 Hefei | File:Hefei Metro Logo.png |
| 乌鲁木齐 Ürümqi | File:URUMQI METRO LOGO.png |
| 呼和浩特 Hohhot | File:Hohhot Metro Logo v1.png |
| 太原 Taiyuan | File:Taiyuan metro logo.png |
| 芜湖 Wuhu | File:Wuhu RT Logo.png |
| 滁州 Chuzhou | File:滁州轨道logo.jpg |

## Not yet found — search not completed (25)

The city's zh.wikipedia article image list contained no logo file, and the
follow-up Commons/zh file search could not be run because of the HTTP 429
hard stop. These are **not** confirmed missing from Wikimedia — they are
simply unsearched. Do not treat as "no logo exists".

武汉 Wuhan · 苏州 Suzhou · 昆明 Kunming · 佛山 Foshan · 宁波 Ningbo ·
淮安 Huai'an (tram) · 东莞 Dongguan · 石家庄 Shijiazhuang · 贵阳 Guiyang ·
厦门 Xiamen · 天水 Tianshui (tram) · 三亚 Sanya (tram) · 株洲 Zhuzhou (ART) ·
宜宾 Yibin (ART) · 洛阳 Luoyang · 嘉兴 Jiaxing (tram) · 绍兴 Shaoxing ·
文山州 Wenshan (tram) · 南平 Nanping (Wuyi tram) · 南通 Nantong ·
台州 Taizhou · 黄石 Huangshi (tram) · 盐城 Yancheng · 红河州 Honghe (tram) ·
许昌 Xuchang (Zhengxu line)
