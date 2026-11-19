# Build the self-contained offline page for the metro map app.
# Run on the macOS Actions runner (or locally): downloads the production
# map SVG + PDF from the author's Tencent COS CDN and the JS libs from
# unpkg, then adapts template.html (upstream SierraQin/metro index.html)
# into offline/index.html with everything inlined/local.
# Output: offline/ (index.html + 3 JS libs + PDF)
import re, shutil, urllib.request, pathlib

BASE = pathlib.Path(__file__).resolve().parent
VENDOR = BASE / "vendor"
OUT = BASE / "offline"
VENDOR.mkdir(exist_ok=True)
OUT.mkdir(exist_ok=True)

URLS = {
    "MTR2.8.0.svg": "https://metro-1252278458.cos.ap-beijing.myqcloud.com/svg/MTR2.8.0.svg",
    "MTR2.8.0.pdf": "https://metro-1252278458.cos.ap-beijing.myqcloud.com/MTR/MTR2.8.0.pdf",
    "vue.global.prod.js": "https://unpkg.com/vue@3.2.29/dist/vue.global.prod.js",
    "hammer.min.js": "https://unpkg.com/hammerjs@2.0.8/hammer.min.js",
    "svg-pan-zoom.js": "https://unpkg.com/svg-pan-zoom@3.6.1/dist/svg-pan-zoom.js",
}

for name, url in URLS.items():
    dest = VENDOR / name
    if dest.exists():
        print("reuse", name, dest.stat().st_size)
        continue
    print("download", url)
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=120) as r, open(dest, "wb") as f:
        shutil.copyfileobj(r, f)
    print(" ->", name, dest.stat().st_size)

html = (BASE / "template.html").read_text(encoding="utf-8")
svg = (VENDOR / "MTR2.8.0.svg").read_text(encoding="utf-8")
assert "</script" not in svg, "SVG must not contain </script"
assert "id=\"svg8\"" in svg

def sub_once(pattern, repl, text, name, flags=0):
    new, n = re.subn(pattern, repl, text, count=1, flags=flags)
    assert n == 1, f"pattern not found exactly once: {name}"
    return new

# A. favicon -> inline data URI + mobile viewport / app-capable metas
html = sub_once(
    r'<link rel="icon" href="https://[^"]+">',
    '<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns=\'http://www.w3.org/2000/svg\' viewBox=\'0 0 64 64\'%3E%3Crect width=\'64\' height=\'64\' rx=\'12\' fill=\'%23003380\'/%3E%3Ctext x=\'32\' y=\'45\' font-size=\'36\' font-family=\'sans-serif\' font-weight=\'bold\' fill=\'white\' text-anchor=\'middle\'%3EM%3C/text%3E%3C/svg%3E">\n'
    '\t\t<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover" />\n'
    '\t\t<meta name="apple-mobile-web-app-capable" content="yes" />\n'
    '\t\t<meta name="apple-mobile-web-app-status-bar-style" content="default" />\n'
    '\t\t<meta name="theme-color" content="#003380" />',
    html, "favicon+viewport")

# B. unpkg scripts -> local files
html = sub_once(r'<script src="https://unpkg\.com/vue@3\.2\.29/dist/vue\.global\.prod\.js"></script>',
                '<script src="vue.global.prod.js"></script>', html, "vue")
html = sub_once(r'<script src="https://unpkg\.com/hammerjs@2\.0\.8/hammer\.min\.js"></script>',
                '<script src="hammer.min.js"></script>', html, "hammer")
html = sub_once(r'<script src="https://unpkg\.com/svg-pan-zoom@3\.6\.1/dist/svg-pan-zoom\.js"></script>',
                '<script src="svg-pan-zoom.js"></script>', html, "svg-pan-zoom")

# C. drop the stale CDN announcement popup script
html = sub_once(r'\s*<script src="https://metro-1252278458\.cos\.ap-beijing\.myqcloud\.com/mpVars/mtr\.qinxr\.cn_index\.js"></script>\n',
                '\n', html, "mpVars script")

# D. drop the uList block (CDN / GitHub API endpoints, no longer used)
html = sub_once(r'\n\t\t\tvar uList = \{.*?\n\t\t\t\};\n', '\n', html, "uList", flags=re.DOTALL)

# E. replace loadProd + loadDev with a local loader reading the inlined SVG
new_loader = '''\t\t\tfunction loadProd() {
\t\t\t\tvar raw = document.getElementById("svgData").textContent;
\t\t\t\tenv.prod.json = { mtrVer: "2.8.0", mtrDate: "2026-07-14" };
\t\t\t\tenv.prod.verName = "MTR2.8.0";
\t\t\t\tenv.prod.verInfo = "{ MTR2.8.0.svg , 2026-07-14 , SierraQin , CC0 1.0 }";
\t\t\t\tenv.prod.pdfUrl = "MTR2.8.0.pdf";
\t\t\t\tenv.prod.svgDom = raw.slice(raw.indexOf("<svg"));
\t\t\t\tenv.prod.success = true;
\t\t\t\tenv.curr = "PROD";
\t\t\t\tvm.curr = env.prod;
\t\t\t};
'''
html = sub_once(r'\n\t\t\tfunction loadProd\(u\) \{.*?\n\t\t\tfunction setPanZoom\(\) \{',
                '\n' + new_loader + '\n\t\t\tfunction setPanZoom() {',
                html, "loadProd+loadDev", flags=re.DOTALL)

# F. drop the "查看开发版" side-menu item
html = sub_once(r',\s*\{\s*text: "查看开发版",\s*icon: "",\s*onclick: "switchEnv\(\)"\s*\}',
                '', html, "dev menu item", flags=re.DOTALL)

# G. startup: call loadProd() directly; delete the switchEnv function
html = sub_once(r'\n\t\t\tswitchEnv\(\);', '\n\t\t\tloadProd();', html, "startup call")
html = sub_once(r'\n\t\t\tfunction switchEnv\(\) \{.*?\n\t\t\t\};\n', '\n',
                html, "switchEnv def", flags=re.DOTALL)

# H. inline the production SVG as plain text before the main script
svg_block = '<script type="text/plain" id="svgData">' + svg + '</script>\n\n\t\t'
html = sub_once(r'\n\t\t<script>\n\t\t\t//const pxSize',
                '\n\t\t' + svg_block + '<script>\n\t\t\t//const pxSize',
                html, "svgData block")

# I. inline the station index + Beijing logo (repo files, built into the page).
# stations.json is generated by gen_stations.py from the same SVG version
# (pypinyin is not on the Actions runner, so the index is precomputed).
stations = (BASE / "stations.json").read_text(encoding="utf-8")
logo_b64 = (BASE / "beijing-logo.b64").read_text(encoding="utf-8").strip()
assert "</script" not in stations, "stations json must not contain </script"
html = sub_once(r'/\*__METRO_STATIONS__\*/\[\]', lambda _: stations, html, "stations json")
html = sub_once(r'/\*__BJ_LOGO__\*/', lambda _: logo_b64, html, "bj logo")

# J. inline the route graph (routes.json, built by finalize_routes.py).
routes = (BASE / "routes.json").read_text(encoding="utf-8")
assert "</script" not in routes, "routes json must not contain </script"
html = sub_once(r'/\*__METRO_ROUTES__\*/null', lambda _: routes, html, "routes json")

# J2. inline the Beijing schematic line map (线路图, RMP Gallery Beijing,
# rendered with the RMP app; see beijing/NOTES.md). This is the SECOND
# Beijing map: beijing/map.svg stays the 配线图 (track layout). The
# 417 stations in stations-line.json are the 418 app stations minus
# 红庙 (drawn on neither map and in no route). The 3 Line 18 stations
# are drawn on the SVG but are NOT in stations-line.json (not in the
# shared routes.json Line 18 route — searchable-but-unroutable otherwise).
import json as _json
bj_line_map = (BASE / "beijing" / "map-line.svg").read_text(encoding="utf-8")
bj_line_stations = (BASE / "beijing" / "stations-line.json").read_text(encoding="utf-8")
assert "</script" not in bj_line_map, "bj line map svg must not contain </script"
assert "</script" not in bj_line_stations, "bj line stations json must not contain </script"
html = sub_once(r'/\*__BJ_LINE_MAP__\*/""', lambda _: _json.dumps(bj_line_map), html, "bj line map svg")
html = sub_once(r'/\*__BJ_LINE_STATIONS__\*/\[\]', lambda _: bj_line_stations, html, "bj line stations json")

# K. inline the Shenyang Metro data (6 operating lines, no Line 6).
# stations/routes are precomputed from Wikipedia line tables (see
# shenyang/NOTES.md); the map is the user's JPG wrapped in an SVG so
# svg-pan-zoom can pan/zoom it like the Beijing vector map.
import json as _json
sy_stations = (BASE / "shenyang" / "stations.json").read_text(encoding="utf-8")
sy_routes = (BASE / "shenyang" / "routes.json").read_text(encoding="utf-8")
sy_map = (BASE / "shenyang" / "map.svg").read_text(encoding="utf-8")
sy_logo_b64 = (BASE / "shenyang" / "logo.b64").read_text(encoding="utf-8").strip()
assert "</script" not in sy_stations, "sy stations json must not contain </script"
assert "</script" not in sy_routes, "sy routes json must not contain </script"
assert "</script" not in sy_map, "sy map svg must not contain </script"
html = sub_once(r'/\*__SY_STATIONS__\*/\[\]', lambda _: sy_stations, html, "sy stations json")
html = sub_once(r'/\*__SY_ROUTES__\*/null', lambda _: sy_routes, html, "sy routes json")
html = sub_once(r'/\*__SY_MAP__\*/""', lambda _: _json.dumps(sy_map), html, "sy map svg")
html = sub_once(r'/\*__SY_LOGO__\*/', lambda _: sy_logo_b64, html, "sy logo")

# L. inline the virtual-transfer data + walking icon (Beijing).
# transfers.json is hand-maintained (Wikipedia 转乘站); the icon is the
# user's walking pictogram with its white background made transparent.
transfers = (BASE / "transfers.json").read_text(encoding="utf-8")
walk_b64 = (BASE / "walk-icon.b64").read_text(encoding="utf-8").strip()
assert "</script" not in transfers, "transfers json must not contain </script"
html = sub_once(r'/\*__METRO_TRANSFERS__\*/\{\}', lambda _: transfers, html, "transfers json")
html = sub_once(r'/\*__WALK_ICON__\*/', lambda _: walk_b64, html, "walk icon")
fare_b64 = (BASE / "wallet-icon.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__FARE_ICON__\*/', lambda _: fare_b64, html, "fare icon")

# L2. inline the per-city virtual-transfer data (same format as Beijing's
# transfers.json; each file is hand-maintained — see TRANSFERS-NOTES.md).
# Empty {} when a city has no verified virtual transfer. Chongqing's
# researched pairs (歇台子/玉带山/观音桥/杨家坪） are NOT wired yet
# (玉带山 passage expiry risk — re-check before wiring); its file is {}. 
sy_transfers = (BASE / "shenyang" / "transfers.json").read_text(encoding="utf-8")
sh_transfers = (BASE / "shanghai" / "transfers.json").read_text(encoding="utf-8")
hb_transfers = (BASE / "harbin" / "transfers.json").read_text(encoding="utf-8")
dl_transfers = (BASE / "dalian" / "transfers.json").read_text(encoding="utf-8")
jh_transfers = (BASE / "jinhua" / "transfers.json").read_text(encoding="utf-8")
cz_transfers = (BASE / "changzhou" / "transfers.json").read_text(encoding="utf-8")
cq_transfers = (BASE / "chongqing" / "transfers.json").read_text(encoding="utf-8")
for _t in (sy_transfers, sh_transfers, hb_transfers, dl_transfers, jh_transfers, cz_transfers, cq_transfers):
    assert "</script" not in _t, "per-city transfers json must not contain </script"
html = sub_once(r'/\*__SY_TRANSFERS__\*/\{\}', lambda _: sy_transfers, html, "sy transfers json")
html = sub_once(r'/\*__SH_TRANSFERS__\*/\{\}', lambda _: sh_transfers, html, "sh transfers json")
html = sub_once(r'/\*__HB_TRANSFERS__\*/\{\}', lambda _: hb_transfers, html, "hb transfers json")
html = sub_once(r'/\*__DL_TRANSFERS__\*/\{\}', lambda _: dl_transfers, html, "dl transfers json")
html = sub_once(r'/\*__JH_TRANSFERS__\*/\{\}', lambda _: jh_transfers, html, "jh transfers json")
html = sub_once(r'/\*__CZ_TRANSFERS__\*/\{\}', lambda _: cz_transfers, html, "cz transfers json")
html = sub_once(r'/\*__CQ_TRANSFERS__\*/\{\}', lambda _: cq_transfers, html, "cq transfers json")
# Shenzhen virtual transfers are NOT yet built (湖贝 / 福田口岸 /
# 红岭南 counterparts + distances unverified) — SZ_TRANSFERS is empty.
html = sub_once(r'/\*__SZ_TRANSFERS__\*/\{\}', lambda _: '{}', html, "sz transfers json")

# M. inline the per-city splash (launch) images.
# BJ splash = the native LaunchScreen image (app/splash.b64, Beijing 北京/配线查询);
# SY splash = the user's Shenyang 沈阳/配线查询 image (web/shenyang/splash.b64).
bj_splash_b64 = (BASE.parent / "app" / "splash.b64").read_text(encoding="utf-8").strip()
sy_splash_b64 = (BASE / "shenyang" / "splash.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__BJ_SPLASH__\*/', lambda _: bj_splash_b64, html, "bj splash")
html = sub_once(r'/\*__SY_SPLASH__\*/', lambda _: sy_splash_b64, html, "sy splash")
bj_splash_dark_b64 = (BASE.parent / "app" / "splash-dark.b64").read_text(encoding="utf-8").strip()
sy_splash_dark_b64 = (BASE / "shenyang" / "splash-dark.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__BJ_SPLASH_DARK__\*/', lambda _: bj_splash_dark_b64, html, "bj splash dark")
html = sub_once(r'/\*__SY_SPLASH_DARK__\*/', lambda _: sy_splash_dark_b64, html, "sy splash dark")

# N. inline the transit-app icons (App Store artwork, 120x120 PNG,
# rounded corners, transparent background; see web/*-icon.b64).
# Beijing Yikatong / Shenyang Shengjing Tong / Shanghai Metro大都会.
ykt_b64 = (BASE / "yikatong-icon.b64").read_text(encoding="utf-8").strip()
sjt_b64 = (BASE / "shengjingtong-icon.b64").read_text(encoding="utf-8").strip()
mddh_b64 = (BASE / "metrodaduhui-icon.b64").read_text(encoding="utf-8").strip()
hbct_b64 = (BASE / "harbinchengshitong-icon.b64").read_text(encoding="utf-8").strip()
dljt_b64 = (BASE / "dalianjiaotong-icon.b64").read_text(encoding="utf-8").strip()
rwx_b64 = (BASE / "renwoxing-icon.b64").read_text(encoding="utf-8").strip()
czm_b64 = (BASE / "czmetro-icon.b64").read_text(encoding="utf-8").strip()
ycx_b64 = (BASE / "yuchangxing-icon.b64").read_text(encoding="utf-8").strip()
cce_b64 = (BASE / "ccmetro-icon.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__YKT_ICON__\*/', lambda _: ykt_b64, html, "yikatong icon")
html = sub_once(r'/\*__SJT_ICON__\*/', lambda _: sjt_b64, html, "shengjingtong icon")
html = sub_once(r'/\*__MDDH_ICON__\*/', lambda _: mddh_b64, html, "metrodaduhui icon")
html = sub_once(r'/\*__HBCT_ICON__\*/', lambda _: hbct_b64, html, "harbin city pass icon")
html = sub_once(r'/\*__DLJT_ICON__\*/', lambda _: dljt_b64, html, "dalian traffic icon")
html = sub_once(r'/\*__RWX_ICON__\*/', lambda _: rwx_b64, html, "renwoxing icon")
html = sub_once(r'/\*__CZM_ICON__\*/', lambda _: czm_b64, html, "changzhou metro icon")
html = sub_once(r'/\*__YCX_ICON__\*/', lambda _: ycx_b64, html, "yuchangxing icon")
html = sub_once(r'/\*__CCE_ICON__\*/', lambda _: cce_b64, html, "changchun e-travel icon")

# O. inline the Shanghai Metro data (22 operating lines, 413 stations).
# Same pattern as Shenyang (step K): precomputed stations/routes from
# the Shanghai dataset (see shanghai/NOTES.md); the map is the user's
# JPG wrapped in an SVG so svg-pan-zoom can pan/zoom it; the logo is
# cropped from the map's top-left corner; the splash is the user's
# 上海/配线查询 image (shanghai/splash.b64).
sh_stations = (BASE / "shanghai" / "stations.json").read_text(encoding="utf-8")
sh_routes = (BASE / "shanghai" / "routes.json").read_text(encoding="utf-8")
sh_map = (BASE / "shanghai" / "map.svg").read_text(encoding="utf-8")
sh_logo_b64 = (BASE / "shanghai" / "logo.b64").read_text(encoding="utf-8").strip()
sh_splash_b64 = (BASE / "shanghai" / "splash.b64").read_text(encoding="utf-8").strip()
assert "</script" not in sh_stations, "sh stations json must not contain </script"
assert "</script" not in sh_routes, "sh routes json must not contain </script"
assert "</script" not in sh_map, "sh map svg must not contain </script"
html = sub_once(r'/\*__SH_STATIONS__\*/\[\]', lambda _: sh_stations, html, "sh stations json")
html = sub_once(r'/\*__SH_ROUTES__\*/null', lambda _: sh_routes, html, "sh routes json")
html = sub_once(r'/\*__SH_MAP__\*/""', lambda _: _json.dumps(sh_map), html, "sh map svg")
html = sub_once(r'/\*__SH_LOGO__\*/', lambda _: sh_logo_b64, html, "sh logo")
html = sub_once(r'/\*__SH_SPLASH__\*/', lambda _: sh_splash_b64, html, "sh splash")
sh_splash_dark_b64 = (BASE / "shanghai" / "splash-dark.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__SH_SPLASH_DARK__\*/', lambda _: sh_splash_dark_b64, html, "sh splash dark")

# Q. inline the Harbin Metro data (3 operating lines, 73 stations).
# Same pattern as Shenyang/Shanghai (steps K/O): precomputed stations/routes
# from the user's 2026.08 Metro Pro map (see harbin/NOTES.md); the map is
# the user's JPG wrapped in an SVG so svg-pan-zoom can pan/zoom it; the logo
# is cropped from the map's title box; the splash is the user's 哈尔滨/配线查询
# image (harbin/splash.b64, from splash-user.jpg).
hb_stations = (BASE / "harbin" / "stations.json").read_text(encoding="utf-8")
hb_routes = (BASE / "harbin" / "routes.json").read_text(encoding="utf-8")
hb_map = (BASE / "harbin" / "map.svg").read_text(encoding="utf-8")
hb_logo_b64 = (BASE / "harbin" / "logo.b64").read_text(encoding="utf-8").strip()
hb_splash_b64 = (BASE / "harbin" / "splash.b64").read_text(encoding="utf-8").strip()
assert "</script" not in hb_stations, "hb stations json must not contain </script"
assert "</script" not in hb_routes, "hb routes json must not contain </script"
assert "</script" not in hb_map, "hb map svg must not contain </script"
html = sub_once(r'/\*__HB_STATIONS__\*/\[\]', lambda _: hb_stations, html, "hb stations json")
html = sub_once(r'/\*__HB_ROUTES__\*/null', lambda _: hb_routes, html, "hb routes json")
html = sub_once(r'/\*__HB_MAP__\*/""', lambda _: _json.dumps(hb_map), html, "hb map svg")
html = sub_once(r'/\*__HB_LOGO__\*/', lambda _: hb_logo_b64, html, "hb logo")
html = sub_once(r'/\*__HB_SPLASH__\*/', lambda _: hb_splash_b64, html, "hb splash")
hb_splash_dark_b64 = (BASE / "harbin" / "splash-dark.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__HB_SPLASH_DARK__\*/', lambda _: hb_splash_dark_b64, html, "hb splash dark")

# R. inline the Dalian Metro data (6 operating lines, 100 stations).
# Same pattern as Shenyang/Shanghai/Harbin (steps K/O/Q): precomputed
# stations/routes from the user's Rail Map Painter map (see dalian/NOTES-dl.md);
# the map is the user's JPG wrapped in an SVG so svg-pan-zoom can pan/zoom it;
# the logo is the official Dalian Metro mark (Wikimedia, blue circle-D-Z);
# the splash is the user's 大连/配线查询 image (dalian/splash.b64, from
# splash-user.jpg). Line 3 branch is a separate "3B" line (not a loop).
dl_stations = (BASE / "dalian" / "stations.json").read_text(encoding="utf-8")
dl_routes = (BASE / "dalian" / "routes.json").read_text(encoding="utf-8")
dl_map = (BASE / "dalian" / "map.svg").read_text(encoding="utf-8")
dl_logo_b64 = (BASE / "dalian" / "logo.b64").read_text(encoding="utf-8").strip()
dl_splash_b64 = (BASE / "dalian" / "splash.b64").read_text(encoding="utf-8").strip()
assert "</script" not in dl_stations, "dl stations json must not contain </script"
assert "</script" not in dl_routes, "dl routes json must not contain </script"
assert "</script" not in dl_map, "dl map svg must not contain </script"
html = sub_once(r'/\*__DL_STATIONS__\*/\[\]', lambda _: dl_stations, html, "dl stations json")
html = sub_once(r'/\*__DL_ROUTES__\*/null', lambda _: dl_routes, html, "dl routes json")
html = sub_once(r'/\*__DL_MAP__\*/""', lambda _: _json.dumps(dl_map), html, "dl map svg")
html = sub_once(r'/\*__DL_LOGO__\*/', lambda _: dl_logo_b64, html, "dl logo")
html = sub_once(r'/\*__DL_SPLASH__\*/', lambda _: dl_splash_b64, html, "dl splash")
dl_splash_dark_b64 = (BASE / "dalian" / "splash-dark.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__DL_SPLASH_DARK__\*/', lambda _: dl_splash_dark_b64, html, "dl splash dark")

# S. inline the Jinhua Rail Transit data (Jinyi East Line, 2 routes, 29 stations).
# Same pattern as Harbin/Dalian: precomputed stations/routes from the user's
# ink-wash map (see jinhua/NOTES.md); the logo is the official mark
# (Wikimedia); the splash is the user's real image (web/jinhua/splash.b64).
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
jh_splash_dark_b64 = (BASE / "jinhua" / "splash-dark.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__JH_SPLASH_DARK__\*/', lambda _: jh_splash_dark_b64, html, "jh splash dark")

# S2. inline the Changzhou Metro data (2 operating lines, 43 stations).
# Same pattern as Jinhua: precomputed stations/routes from the user's
# schematic map (see changzhou/NOTES.md); Lines 5/6 are drawn on the map
# but under construction and are NOT in the data files.
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
cz_splash_dark_b64 = (BASE / "changzhou" / "splash-dark.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__CZ_SPLASH_DARK__\*/', lambda _: cz_splash_dark_b64, html, "cz splash dark")

# S5. inline the Shenzhen Metro data (17 lines, 351 stations).
# Same pattern as Changzhou: precomputed stations/routes from the RMP
# Gallery map (see shenzhen/NETWORK.md); 20 unopened lines/segments
# are NOT in the data files.
sz_stations = (BASE / "shenzhen" / "stations.json").read_text(encoding="utf-8")
sz_routes = (BASE / "shenzhen" / "routes.json").read_text(encoding="utf-8")
assert "</script" not in sz_stations, "sz stations json must not contain </script"
assert "</script" not in sz_routes, "sz routes json must not contain </script"
html = sub_once(r'/\*__SZ_STATIONS__\*/\[\]', lambda _: sz_stations, html, "sz stations json")
html = sub_once(r'/\*__SZ_ROUTES__\*/null', lambda _: sz_routes, html, "sz routes json")
# map.svg is exported by a browser task and may land after wiring;
# warn and leave the marker empty rather than failing the build.
sz_map_path = BASE / "shenzhen" / "map.svg"
if sz_map_path.exists():
    sz_map = sz_map_path.read_text(encoding="utf-8")
    assert "</script" not in sz_map, "sz map svg must not contain </script"
    html = sub_once(r'/\*__SZ_MAP__\*/""', lambda _: _json.dumps(sz_map), html, "sz map svg")
else:
    print("WARNING: web/shenzhen/map.svg missing; Shenzhen map will be empty")
# Shenzhen splash (user-supplied 深圳/配线查询 image, web/shenzhen/splash.b64,
# JPEG). The template uses the empty-string comment pattern
# (window.SZ_SPLASH = /*__SZ_SPLASH__*/''), so match the marker + '' and
# replace with a quoted JPEG data URL. Logo: official Shenzhen Metro
# Corporation logo (Wikimedia), web/shenzhen/logo.b64 (PNG), same
# empty-string pattern as the splash.
sz_splash_path = BASE / "shenzhen" / "splash.b64"
if sz_splash_path.exists():
    sz_splash_b64 = sz_splash_path.read_text(encoding="utf-8").strip()
    html = sub_once(r"/\*__SZ_SPLASH__\*/''", lambda _: "'data:image/jpeg;base64," + sz_splash_b64 + "'", html, "sz splash")
else:
    print("WARNING: web/shenzhen/splash.b64 missing; Shenzhen splash will be empty")
sz_splash_dark_path = BASE / "shenzhen" / "splash-dark.b64"
if sz_splash_dark_path.exists():
    sz_splash_dark_b64 = sz_splash_dark_path.read_text(encoding="utf-8").strip()
    html = sub_once(r"/\*__SZ_SPLASH_DARK__\*/''", lambda _: "'data:image/jpeg;base64," + sz_splash_dark_b64 + "'", html, "sz splash dark")
else:
    print("WARNING: web/shenzhen/splash-dark.b64 missing; Shenzhen dark splash will be empty")
sz_logo_path = BASE / "shenzhen" / "logo.b64"
if sz_logo_path.exists():
    sz_logo_b64 = sz_logo_path.read_text(encoding="utf-8").strip()
    html = sub_once(r"/\*__SZ_LOGO__\*/''", lambda _: "'data:image/png;base64," + sz_logo_b64 + "'", html, "sz logo")
else:
    print("WARNING: web/shenzhen/logo.b64 missing; Shenzhen logo will be empty")

# S6. inline the Chengdu Metro data (17 operating lines, 364 stations).
# Same pattern as Changchun: precomputed stations/routes from the RMP
# Gallery map (see chengdu/NOTES.md); the T2 tram, the 6 built-but-
# unopened stations (白仁店, 玉虹路, 分水, 天府机场3号4号航站楼, 合江,
# 芦葭), the Line 10 third-phase platforms, 18号线三期 and S5/S11 are
# drawn on the map or under construction but are NOT in the data files.
cd_stations = (BASE / "chengdu" / "stations.json").read_text(encoding="utf-8")
cd_routes = (BASE / "chengdu" / "routes.json").read_text(encoding="utf-8")
cd_map = (BASE / "chengdu" / "map.svg").read_text(encoding="utf-8")
assert "</script" not in cd_stations, "cd stations json must not contain </script"
assert "</script" not in cd_routes, "cd routes json must not contain </script"
assert "</script" not in cd_map, "cd map svg must not contain </script"
html = sub_once(r'/\*__CD_STATIONS__\*/\[\]', lambda _: cd_stations, html, "cd stations json")
html = sub_once(r'/\*__CD_ROUTES__\*/null', lambda _: cd_routes, html, "cd routes json")
html = sub_once(r'/\*__CD_MAP__\*/""', lambda _: _json.dumps(cd_map), html, "cd map svg")
# Chengdu logo (official Chengdu Rail Transit icon, Wikimedia) and splash
# (user-supplied 成都/配线查询 image), both in web/chengdu/*.b64. The splash
# is a JPEG inlined under the template's image/png data URL, the same
# convention as the other cities' JPEG splashes.
cd_logo_path = BASE / "chengdu" / "logo.b64"
if cd_logo_path.exists():
    cd_logo_b64 = cd_logo_path.read_text(encoding="utf-8").strip()
    html = sub_once(r'/\*__CD_LOGO__\*/', lambda _: cd_logo_b64, html, "cd logo")
else:
    print("WARNING: web/chengdu/logo.b64 missing; Chengdu logo will be empty")
cd_splash_path = BASE / "chengdu" / "splash.b64"
if cd_splash_path.exists():
    cd_splash_b64 = cd_splash_path.read_text(encoding="utf-8").strip()
    html = sub_once(r'/\*__CD_SPLASH__\*/', lambda _: cd_splash_b64, html, "cd splash")
else:
    print("WARNING: web/chengdu/splash.b64 missing; Chengdu splash will be empty")
cd_splash_dark_path = BASE / "chengdu" / "splash-dark.b64"
if cd_splash_dark_path.exists():
    cd_splash_dark_b64 = cd_splash_dark_path.read_text(encoding="utf-8").strip()
    html = sub_once(r'/\*__CD_SPLASH_DARK__\*/', lambda _: cd_splash_dark_b64, html, "cd splash dark")
else:
    print("WARNING: web/chengdu/splash-dark.b64 missing; Chengdu dark splash will be empty")

# S7. inline the Qingdao Metro data (8 operating lines, 176 stations).
# Same pattern as Chengdu: precomputed stations/routes from the RMP
# Gallery map v79 (see qingdao/NOTES.md); unopened lines (2号线二期, 5,
# 6号线二期, 7号线二期, 8号线支线, 9, 15, 蓝谷快线二期) and the built-
# but-unopened 东南山 are NOT in the data files.
qd_stations = (BASE / "qingdao" / "stations.json").read_text(encoding="utf-8")
qd_routes = (BASE / "qingdao" / "routes.json").read_text(encoding="utf-8")
qd_map = (BASE / "qingdao" / "map.svg").read_text(encoding="utf-8")
assert "</script" not in qd_stations, "qd stations json must not contain </script"
assert "</script" not in qd_routes, "qd routes json must not contain </script"
assert "</script" not in qd_map, "qd map svg must not contain </script"
html = sub_once(r'/\*__QD_STATIONS__\*/\[\]', lambda _: qd_stations, html, "qd stations json")
html = sub_once(r'/\*__QD_ROUTES__\*/null', lambda _: qd_routes, html, "qd routes json")
html = sub_once(r'/\*__QD_MAP__\*/""', lambda _: _json.dumps(qd_map), html, "qd map svg")
# Qingdao logo (official Qingdao Metro lockup, Wikimedia) and splash
# (user-supplied 青岛/配线查询 image), both in web/qingdao/*.b64.
qd_logo_path = BASE / "qingdao" / "logo.b64"
if qd_logo_path.exists():
    qd_logo_b64 = qd_logo_path.read_text(encoding="utf-8").strip()
    html = sub_once(r'/\*__QD_LOGO__\*/', lambda _: qd_logo_b64, html, "qd logo")
else:
    print("WARNING: web/qingdao/logo.b64 missing; Qingdao logo will be empty")
qd_splash_path = BASE / "qingdao" / "splash.b64"
if qd_splash_path.exists():
    qd_splash_b64 = qd_splash_path.read_text(encoding="utf-8").strip()
    html = sub_once(r'/\*__QD_SPLASH__\*/', lambda _: qd_splash_b64, html, "qd splash")
else:
    print("WARNING: web/qingdao/splash.b64 missing; Qingdao splash will be empty")
qd_splash_dark_path = BASE / "qingdao" / "splash-dark.b64"
if qd_splash_dark_path.exists():
    qd_splash_dark_b64 = qd_splash_dark_path.read_text(encoding="utf-8").strip()
    html = sub_once(r'/\*__QD_SPLASH_DARK__\*/', lambda _: qd_splash_dark_b64, html, "qd splash dark")
else:
    print("WARNING: web/qingdao/splash-dark.b64 missing; Qingdao dark splash will be empty")

# S3. inline the Chongqing Rail Transit data (14 lines, 282 stations).
# Same pattern as Jinhua/Changzhou: precomputed stations/routes from the
# user's system-plan map (see chongqing/NOTES.md); the logo is cropped
# from the map; the splash is the user's real image, edited (see NOTES.md).
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
cq_splash_dark_b64 = (BASE / "chongqing" / "splash-dark.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__CQ_SPLASH_DARK__\*/', lambda _: cq_splash_dark_b64, html, "cq splash dark")

# S4. inline the Changchun Rail Transit data (8 operating lines, 142 stations).
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
cc_splash_dark_b64 = (BASE / "changchun" / "splash-dark.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__CC_SPLASH_DARK__\*/', lambda _: cc_splash_dark_b64, html, "cc splash dark")

# P. inline the first/last-train timetable data (web/timetable/*.json,
# Sun-Thu standard timetable) + the user's calendar-clock tab icon.
bj_tt = (BASE / "timetable" / "bj.json").read_text(encoding="utf-8")
sy_tt = (BASE / "timetable" / "sy.json").read_text(encoding="utf-8")
sh_tt = (BASE / "timetable" / "sh.json").read_text(encoding="utf-8")
hb_tt = (BASE / "timetable" / "hb.json").read_text(encoding="utf-8")
dl_tt = (BASE / "timetable" / "dl.json").read_text(encoding="utf-8")
jh_tt = (BASE / "timetable" / "jh.json").read_text(encoding="utf-8")
cz_tt = (BASE / "timetable" / "cz.json").read_text(encoding="utf-8")
cq_tt = (BASE / "timetable" / "cq.json").read_text(encoding="utf-8")
cc_tt = (BASE / "timetable" / "cc.json").read_text(encoding="utf-8")
sz_tt = (BASE / "timetable" / "sz.json").read_text(encoding="utf-8")
cd_tt = (BASE / "timetable" / "cd.json").read_text(encoding="utf-8")
qd_tt_path = BASE / "timetable" / "qd.json"
qd_tt = qd_tt_path.read_text(encoding="utf-8") if qd_tt_path.exists() else "{}"
tt_icon_b64 = (BASE / "timetable-icon.b64").read_text(encoding="utf-8").strip()
assert "</script" not in bj_tt, "bj timetable json must not contain </script"
assert "</script" not in sy_tt, "sy timetable json must not contain </script"
assert "</script" not in sh_tt, "sh timetable json must not contain </script"
assert "</script" not in hb_tt, "hb timetable json must not contain </script"
assert "</script" not in dl_tt, "dl timetable json must not contain </script"
assert "</script" not in jh_tt, "jh timetable json must not contain </script"
assert "</script" not in cz_tt, "cz timetable json must not contain </script"
assert "</script" not in cq_tt, "cq timetable json must not contain </script"
assert "</script" not in cc_tt, "cc timetable json must not contain </script"
assert "</script" not in sz_tt, "sz timetable json must not contain </script"
assert "</script" not in cd_tt, "cd timetable json must not contain </script"
assert "</script" not in qd_tt, "qd timetable json must not contain </script"
html = sub_once(r'/\*__BJ_TIMETABLE__\*/\{\}', lambda _: bj_tt, html, "bj timetable json")
html = sub_once(r'/\*__SY_TIMETABLE__\*/\{\}', lambda _: sy_tt, html, "sy timetable json")
html = sub_once(r'/\*__SH_TIMETABLE__\*/\{\}', lambda _: sh_tt, html, "sh timetable json")
html = sub_once(r'/\*__HB_TIMETABLE__\*/\{\}', lambda _: hb_tt, html, "hb timetable json")
html = sub_once(r'/\*__DL_TIMETABLE__\*/\{\}', lambda _: dl_tt, html, "dl timetable json")
html = sub_once(r'/\*__JH_TIMETABLE__\*/\{\}', lambda _: jh_tt, html, "jh timetable json")
html = sub_once(r'/\*__CZ_TIMETABLE__\*/\{\}', lambda _: cz_tt, html, "cz timetable json")
html = sub_once(r'/\*__CQ_TIMETABLE__\*/\{\}', lambda _: cq_tt, html, "cq timetable json")
html = sub_once(r'/\*__CC_TIMETABLE__\*/\{\}', lambda _: cc_tt, html, "cc timetable json")
html = sub_once(r'/\*__SZ_TIMETABLE__\*/\{\}', lambda _: sz_tt, html, "sz timetable json")
html = sub_once(r'/\*__CD_TIMETABLE__\*/\{\}', lambda _: cd_tt, html, "cd timetable json")
html = sub_once(r'/\*__QD_TIMETABLE__\*/\{\}', lambda _: qd_tt, html, "qd timetable json")
html = sub_once(r'/\*__TT_ICON__\*/', lambda _: tt_icon_b64, html, "timetable icon")

# U. inline verified station lat/lng (web/latlng/latlng-{city}.json,
# Wikidata-sourced, 6 decimals; name -> [lat, lng]). Unmatched stations
# are simply absent from a table — never invented or interpolated. The
# web merges each city's table into its station objects by exact Chinese
# name (see applyLatLng in template.html); stations without a match keep
# no lat/lng and are skipped by the nearest-station search.
bj_ll = (BASE / "latlng" / "latlng-bj.json").read_text(encoding="utf-8")
sy_ll = (BASE / "latlng" / "latlng-sy.json").read_text(encoding="utf-8")
sh_ll = (BASE / "latlng" / "latlng-sh.json").read_text(encoding="utf-8")
hb_ll = (BASE / "latlng" / "latlng-hb.json").read_text(encoding="utf-8")
dl_ll = (BASE / "latlng" / "latlng-dl.json").read_text(encoding="utf-8")
jh_ll = (BASE / "latlng" / "latlng-jh.json").read_text(encoding="utf-8")
cz_ll = (BASE / "latlng" / "latlng-cz.json").read_text(encoding="utf-8")
cq_ll = (BASE / "latlng" / "latlng-cq.json").read_text(encoding="utf-8")
cc_ll = (BASE / "latlng" / "latlng-cc.json").read_text(encoding="utf-8")
sz_ll = (BASE / "latlng" / "latlng-sz.json").read_text(encoding="utf-8")
cd_ll = (BASE / "latlng" / "latlng-cd.json").read_text(encoding="utf-8")
qd_ll = (BASE / "latlng" / "latlng-qd.json").read_text(encoding="utf-8")
assert "</script" not in bj_ll, "bj latlng json must not contain </script"
assert "</script" not in sy_ll, "sy latlng json must not contain </script"
assert "</script" not in sh_ll, "sh latlng json must not contain </script"
assert "</script" not in hb_ll, "hb latlng json must not contain </script"
assert "</script" not in dl_ll, "dl latlng json must not contain </script"
assert "</script" not in jh_ll, "jh latlng json must not contain </script"
assert "</script" not in cz_ll, "cz latlng json must not contain </script"
assert "</script" not in cq_ll, "cq latlng json must not contain </script"
assert "</script" not in cc_ll, "cc latlng json must not contain </script"
assert "</script" not in sz_ll, "sz latlng json must not contain </script"
assert "</script" not in cd_ll, "cd latlng json must not contain </script"
assert "</script" not in qd_ll, "qd latlng json must not contain </script"
html = sub_once(r'/\*__BJ_LATLNG__\*/\{\}', lambda _: bj_ll, html, "bj latlng json")
html = sub_once(r'/\*__SY_LATLNG__\*/\{\}', lambda _: sy_ll, html, "sy latlng json")
html = sub_once(r'/\*__SH_LATLNG__\*/\{\}', lambda _: sh_ll, html, "sh latlng json")
html = sub_once(r'/\*__HB_LATLNG__\*/\{\}', lambda _: hb_ll, html, "hb latlng json")
html = sub_once(r'/\*__DL_LATLNG__\*/\{\}', lambda _: dl_ll, html, "dl latlng json")
html = sub_once(r'/\*__JH_LATLNG__\*/\{\}', lambda _: jh_ll, html, "jh latlng json")
html = sub_once(r'/\*__CZ_LATLNG__\*/\{\}', lambda _: cz_ll, html, "cz latlng json")
html = sub_once(r'/\*__CQ_LATLNG__\*/\{\}', lambda _: cq_ll, html, "cq latlng json")
html = sub_once(r'/\*__CC_LATLNG__\*/\{\}', lambda _: cc_ll, html, "cc latlng json")
html = sub_once(r'/\*__SZ_LATLNG__\*/\{\}', lambda _: sz_ll, html, "sz latlng json")
html = sub_once(r'/\*__CD_LATLNG__\*/\{\}', lambda _: cd_ll, html, "cd latlng json")
html = sub_once(r'/\*__QD_LATLNG__\*/\{\}', lambda _: qd_ll, html, "qd latlng json")

# S8. inline the verified official metro logos for the not-yet-
# supported cities (web/upcoming-logos/, see its MANIFEST.md): the
# Settings "即将支持" rows show the real logo instead of the generic
# grey M icon. Only visually verified files are listed; Tianjin is
# held back (its Wikimedia source is named "Old Logo" — currency not
# yet confirmed). Cities without a verified logo keep the M icon.
_SOON_LOGO_FILES = {
    "广州": "guangzhou.b64", "南京": "nanjing.b64", "西安": "xian.b64",
    "杭州": "hangzhou.b64", "长沙": "changsha.b64", "无锡": "wuxi.b64",
    "南昌": "nanchang.b64", "福州": "fuzhou.b64", "南宁": "nanning.b64",
    "温州": "wenzhou.b64", "济南": "jinan.b64", "徐州": "xuzhou.b64",
}
_soon_logos = {}
for _name, _fn in _SOON_LOGO_FILES.items():
    _lp = BASE / "upcoming-logos" / _fn
    if _lp.exists():
        _soon_logos[_name] = "data:image/png;base64," + _lp.read_text(encoding="utf-8").strip()
    else:
        print("WARNING: web/upcoming-logos/" + _fn + " missing; " + _name + " keeps the generic icon")
html = sub_once(r'/\*__SOON_LOGOS__\*/\{\}', lambda _: _json.dumps(_soon_logos, ensure_ascii=False), html, "soon logos")

# T. inline the transit briefing seed (web/briefing.json): the 10 upcoming
# lines + the Dalian Line 4 delay. The page renders from this seed when
# offline; when online the app fetches the live file from GitHub and
# caches it in localStorage (see refreshBriefing in template.html).
briefing = (BASE / "briefing.json").read_text(encoding="utf-8")
assert "</script" not in briefing, "briefing json must not contain </script"
html = sub_once(r'/\*__BRIEFING_SEED__\*/\{\}', lambda _: briefing, html, "briefing seed json")

# T2. inline the trains seed (web/trains.json): the 9-city train list for
# the Settings train search. Same offline pattern as the briefing seed.
trains = (BASE / "trains.json").read_text(encoding="utf-8")
assert "</script" not in trains, "trains json must not contain </script"
html = sub_once(r'/\*__TRAINS_SEED__\*/\{\}', lambda _: trains, html, "trains seed json")

out = OUT / "index.html"
out.write_text(html, encoding="utf-8")

for name in ["vue.global.prod.js", "hammer.min.js", "svg-pan-zoom.js", "MTR2.8.0.pdf"]:
    shutil.copy2(VENDOR / name, OUT / name)

print("wrote", out, out.stat().st_size, "bytes")
for p in sorted(OUT.iterdir()):
    print(" ", p.name, p.stat().st_size)
