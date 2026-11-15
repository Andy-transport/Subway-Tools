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

# M. inline the per-city splash (launch) images.
# BJ splash = the native LaunchScreen image (app/splash.b64, Beijing 北京/配线查询);
# SY splash = the user's Shenyang 沈阳/配线查询 image (web/shenyang/splash.b64).
bj_splash_b64 = (BASE.parent / "app" / "splash.b64").read_text(encoding="utf-8").strip()
sy_splash_b64 = (BASE / "shenyang" / "splash.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__BJ_SPLASH__\*/', lambda _: bj_splash_b64, html, "bj splash")
html = sub_once(r'/\*__SY_SPLASH__\*/', lambda _: sy_splash_b64, html, "sy splash")

# N. inline the transit-app icons (App Store artwork, 120x120 PNG,
# rounded corners, transparent background; see web/*-icon.b64).
# Beijing Yikatong / Shenyang Shengjing Tong / Shanghai Metro大都会.
ykt_b64 = (BASE / "yikatong-icon.b64").read_text(encoding="utf-8").strip()
sjt_b64 = (BASE / "shengjingtong-icon.b64").read_text(encoding="utf-8").strip()
mddh_b64 = (BASE / "metrodaduhui-icon.b64").read_text(encoding="utf-8").strip()
hbct_b64 = (BASE / "harbinchengshitong-icon.b64").read_text(encoding="utf-8").strip()
dljt_b64 = (BASE / "dalianjiaotong-icon.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__YKT_ICON__\*/', lambda _: ykt_b64, html, "yikatong icon")
html = sub_once(r'/\*__SJT_ICON__\*/', lambda _: sjt_b64, html, "shengjingtong icon")
html = sub_once(r'/\*__MDDH_ICON__\*/', lambda _: mddh_b64, html, "metrodaduhui icon")
html = sub_once(r'/\*__HBCT_ICON__\*/', lambda _: hbct_b64, html, "harbin city pass icon")
html = sub_once(r'/\*__DLJT_ICON__\*/', lambda _: dljt_b64, html, "dalian traffic icon")

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

# P. inline the first/last-train timetable data (web/timetable/*.json,
# Sun-Thu standard timetable) + the user's calendar-clock tab icon.
bj_tt = (BASE / "timetable" / "bj.json").read_text(encoding="utf-8")
sy_tt = (BASE / "timetable" / "sy.json").read_text(encoding="utf-8")
sh_tt = (BASE / "timetable" / "sh.json").read_text(encoding="utf-8")
hb_tt = (BASE / "timetable" / "hb.json").read_text(encoding="utf-8")
dl_tt = (BASE / "timetable" / "dl.json").read_text(encoding="utf-8")
tt_icon_b64 = (BASE / "timetable-icon.b64").read_text(encoding="utf-8").strip()
assert "</script" not in bj_tt, "bj timetable json must not contain </script"
assert "</script" not in sy_tt, "sy timetable json must not contain </script"
assert "</script" not in sh_tt, "sh timetable json must not contain </script"
assert "</script" not in hb_tt, "hb timetable json must not contain </script"
assert "</script" not in dl_tt, "dl timetable json must not contain </script"
html = sub_once(r'/\*__BJ_TIMETABLE__\*/\{\}', lambda _: bj_tt, html, "bj timetable json")
html = sub_once(r'/\*__SY_TIMETABLE__\*/\{\}', lambda _: sy_tt, html, "sy timetable json")
html = sub_once(r'/\*__SH_TIMETABLE__\*/\{\}', lambda _: sh_tt, html, "sh timetable json")
html = sub_once(r'/\*__HB_TIMETABLE__\*/\{\}', lambda _: hb_tt, html, "hb timetable json")
html = sub_once(r'/\*__DL_TIMETABLE__\*/\{\}', lambda _: dl_tt, html, "dl timetable json")
html = sub_once(r'/\*__TT_ICON__\*/', lambda _: tt_icon_b64, html, "timetable icon")

out = OUT / "index.html"
out.write_text(html, encoding="utf-8")

for name in ["vue.global.prod.js", "hammer.min.js", "svg-pan-zoom.js", "MTR2.8.0.pdf"]:
    shutil.copy2(VENDOR / name, OUT / name)

print("wrote", out, out.stat().st_size, "bytes")
for p in sorted(OUT.iterdir()):
    print(" ", p.name, p.stat().st_size)
