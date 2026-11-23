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

# I2. inline the station structure index (TEST BUILD ONLY feature,
# test/structure branch 2026-11-22). index.json is built by
# gen_structure_index.py from the verified census files. Missing
# index -> empty object, the panel shows "being prepared" everywhere.
# 26E113: the diagram images are NO LONGER inlined — the index carries
# a pinned jsDelivr CDN URL per image (see gen_structure_index.py) and
# the page downloads on demand, caching each viewed image in
# IndexedDB for offline use. STRUCTURE_IMGS stays as an empty object
# (legacy placeholder in the template head, always {} now).
import json as _jsonmod
_struct_index_path = BASE / "structure" / "index.json"
if _struct_index_path.exists():
    _struct_index = _struct_index_path.read_text(encoding="utf-8")
    _struct_data = _jsonmod.loads(_struct_index)
else:
    _struct_index = "{}"
    _struct_data = {}
_n_struct_imgs = sum(1 for _e in _struct_data.values() for _k in ("spatial", "plan") if _e.get(_k))
print("structure index:", len(_struct_data), "stations,", _n_struct_imgs, "images (on-demand via CDN, not inlined)")
assert "</script" not in _struct_index, "structure index must not contain </script"
html = sub_once(r'/\*__STRUCTURE_INDEX__\*/\{\}', lambda _: _struct_index, html, "structure index")
html = sub_once(r'/\*__STRUCTURE_IMGS__\*/\{\}', lambda _: "{}", html, "structure imgs (empty since 26E113)")

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
# L1. inline the Beijing transfer-time estimates (metroman-derived,
# labelled 预估 in the UI; see transfer-times-bj.json + the method
# note in ~/workspace/metroman-research). Placeholder in template:
# /*__BJ_TRANSFER_TIMES__*/{} beside the transfers data field.
bj_tt = (BASE / "transfer-times-bj.json").read_text(encoding="utf-8")
assert "</script" not in bj_tt, "bj transfer times json must not contain </script"
html = sub_once(r'/\*__BJ_TRANSFER_TIMES__\*/\{\}', lambda _: bj_tt, html, "bj transfer times json")
# L1b (26E123). inline the Beijing MEASURED transfer distances
# (user's infographic parse, confirmed entries only; see
# transfer-dist-bj.json) and the virtual-transfer entrance guidance
# (vt-exits-bj.json). Display-only data.
bj_dist = (BASE / "transfer-dist-bj.json").read_text(encoding="utf-8")
assert "</script" not in bj_dist, "bj transfer dist json must not contain </script"
html = sub_once(r'/\*__BJ_TRANSFER_DIST__\*/\{\}', lambda _: bj_dist, html, "bj transfer dist json")
bj_vtx = (BASE / "vt-exits-bj.json").read_text(encoding="utf-8")
assert "</script" not in bj_vtx, "bj vt exits json must not contain </script"
html = sub_once(r'/\*__BJ_VT_EXITS__\*/\[\]', lambda _: bj_vtx, html, "bj vt exits json")
html = sub_once(r'/\*__WALK_ICON__\*/', lambda _: walk_b64, html, "walk icon")
walk_ink_b64 = (BASE / "walk-icon-ink.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__WALK_ICON_INK__\*/', lambda _: walk_ink_b64, html, "walk icon ink")
pin_b64 = (BASE / "pin-icon.b64").read_text(encoding="utf-8").strip()
pin_ink_b64 = (BASE / "pin-icon-ink.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__PIN_ICON__\*/', lambda _: pin_b64, html, "pin icon")
html = sub_once(r'/\*__PIN_ICON_INK__\*/', lambda _: pin_ink_b64, html, "pin icon ink")
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

# Universal launch splash (26D100): one pair for the whole app,
# picked by dark/light only (app/splash-st.b64 / splash-st-dark.b64,
# the same source files build.sh decodes into the bundle).
st_splash_b64 = (BASE.parent / "app" / "splash-st.b64").read_text(encoding="utf-8").strip()
st_splash_dark_b64 = (BASE.parent / "app" / "splash-st-dark.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__ST_SPLASH__\*/', lambda _: st_splash_b64, html, "st splash")
html = sub_once(r'/\*__ST_SPLASH_DARK__\*/', lambda _: st_splash_dark_b64, html, "st splash dark")

# Siri settings-row icon (26D100): the user's Siri-orb artwork as a
# light tile / black tile pair (app/siri-icon.b64 / siri-icon-dark.b64),
# swapped by theme in the page.
siri_icon_b64 = (BASE.parent / "app" / "siri-icon.b64").read_text(encoding="utf-8").strip()
siri_icon_dark_b64 = (BASE.parent / "app" / "siri-icon-dark.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__SIRI_ICON__\*/', lambda _: siri_icon_b64, html, "siri icon")
html = sub_once(r'/\*__SIRI_ICON_DARK__\*/', lambda _: siri_icon_dark_b64, html, "siri icon dark")

# Appearance settings-row icon (26D103): the user's contrast-glyph
# black tile (app/appearance-icon.b64); a single variant used in
# both light and dark themes.
appearance_icon_b64 = (BASE.parent / "app" / "appearance-icon.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__APPEARANCE_ICON__\*/', lambda _: appearance_icon_b64, html, "appearance icon")

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
szm_b64 = (BASE / "szmetro-icon.b64").read_text(encoding="utf-8").strip()
qdm_b64 = (BASE / "qdmetro-icon.b64").read_text(encoding="utf-8").strip()
html = sub_once(r'/\*__SZM_ICON__\*/', lambda _: szm_b64, html, "shenzhen metro app icon")
html = sub_once(r'/\*__QDM_ICON__\*/', lambda _: qdm_b64, html, "qingdao metro app icon")
sjzm_icon_path = BASE / "sjzmetro-icon.b64"
if sjzm_icon_path.exists():
    sjzm_b64 = sjzm_icon_path.read_text(encoding="utf-8").strip()
    html = sub_once(r'/\*__SJZM_ICON__\*/', lambda _: sjzm_b64, html, "shijiazhuang metro app icon")
# 26E116: Tianjin Metro official app icon + Wuxi 码上行 app icon
# (App Store artwork, 120x120 rounded-corner PNG, same treatment as
# the SJZ icon; substitute only when the file exists).
tjm_icon_path = BASE / "tjmetro-icon.b64"
if tjm_icon_path.exists():
    tjm_b64 = tjm_icon_path.read_text(encoding="utf-8").strip()
    html = sub_once(r'/\*__TJM_ICON__\*/', lambda _: tjm_b64, html, "tianjin metro app icon")
msx_icon_path = BASE / "mashangxing-icon.b64"
if msx_icon_path.exists():
    msx_b64 = msx_icon_path.read_text(encoding="utf-8").strip()
    html = sub_once(r'/\*__MSX_ICON__\*/', lambda _: msx_b64, html, "mashangxing app icon")

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

# S9. inline the Shijiazhuang Metro data (3 operating lines, 60 stations).
# Same pattern as Qingdao: precomputed stations/routes from the RMP
# Gallery map v56 (see shijiazhuang/NOTES.md); the unopened Line 1
# extension stations (东上泽/东洋/上庄/槐安路) and Lines 4/5/6 are NOT
# in the data files.
sjz_stations = (BASE / "shijiazhuang" / "stations.json").read_text(encoding="utf-8")
sjz_routes = (BASE / "shijiazhuang" / "routes.json").read_text(encoding="utf-8")
sjz_map = (BASE / "shijiazhuang" / "map.svg").read_text(encoding="utf-8")
assert "</script" not in sjz_stations, "sjz stations json must not contain </script"
assert "</script" not in sjz_routes, "sjz routes json must not contain </script"
assert "</script" not in sjz_map, "sjz map svg must not contain </script"
html = sub_once(r'/\*__SJZ_STATIONS__\*/\[\]', lambda _: sjz_stations, html, "sjz stations json")
html = sub_once(r'/\*__SJZ_ROUTES__\*/null', lambda _: sjz_routes, html, "sjz routes json")
html = sub_once(r'/\*__SJZ_MAP__\*/""', lambda _: _json.dumps(sjz_map), html, "sjz map svg")
# Shijiazhuang logo: the official original is not prepared yet (see
# shijiazhuang/NOTES.md) — substitute only when the file appears,
# mirroring the Shenzhen logo pattern (placeholder default is '').
sjz_logo_path = BASE / "shijiazhuang" / "logo.b64"
if sjz_logo_path.exists():
    sjz_logo_b64 = sjz_logo_path.read_text(encoding="utf-8").strip()
    html = sub_once(r"/\*__SJZ_LOGO__\*/''", lambda _: "'data:image/png;base64," + sjz_logo_b64 + "'", html, "sjz logo")
else:
    print("WARNING: web/shijiazhuang/logo.b64 missing; Shijiazhuang logo will be empty")
sjz_splash_path = BASE / "shijiazhuang" / "splash.b64"
if sjz_splash_path.exists():
    sjz_splash_b64 = sjz_splash_path.read_text(encoding="utf-8").strip()
    html = sub_once(r'/\*__SJZ_SPLASH__\*/', lambda _: sjz_splash_b64, html, "sjz splash")
else:
    print("WARNING: web/shijiazhuang/splash.b64 missing; Shijiazhuang splash will be empty")
sjz_splash_dark_path = BASE / "shijiazhuang" / "splash-dark.b64"
if sjz_splash_dark_path.exists():
    sjz_splash_dark_b64 = sjz_splash_dark_path.read_text(encoding="utf-8").strip()
    html = sub_once(r'/\*__SJZ_SPLASH_DARK__\*/', lambda _: sjz_splash_dark_b64, html, "sjz splash dark")
else:
    print("WARNING: web/shijiazhuang/splash-dark.b64 missing; Shijiazhuang dark splash will be empty")

# S10. inline the Tianjin Metro data (12 operating lines, 229 stations,
# 26E116). Same pattern as Shijiazhuang: precomputed stations/routes
# from the RMP Gallery map v77, triple-cross-checked against the
# Wikipedia station template and the official line table (see the
# staging package SOURCES.md). Line colours are the OFFICIAL ones
# (sampled from the official 2026-07-21 network map), NOT the RMP
# palette. NOT in the data files: the Z4 line (opened 2026-01-18 but
# has no RMP drawing / coordinates — held back like Beijing Line 18's
# missing stations), the closed 新华路, and the built-but-unopened
# 梨双路北/上郭庄/咸水沽北. Line 4 is two disconnected operating
# segments (north 小街—西站, south 东南角—新兴村) with NO edge between
# them in routes.json, so no cross-segment direct ride can be built.
tj_stations = (BASE / "tianjin" / "stations.json").read_text(encoding="utf-8")
tj_routes = (BASE / "tianjin" / "routes.json").read_text(encoding="utf-8")
tj_map = (BASE / "tianjin" / "map.svg").read_text(encoding="utf-8")
assert "</script" not in tj_stations, "tj stations json must not contain </script"
assert "</script" not in tj_routes, "tj routes json must not contain </script"
assert "</script" not in tj_map, "tj map svg must not contain </script"
html = sub_once(r'/\*__TJ_STATIONS__\*/\[\]', lambda _: tj_stations, html, "tj stations json")
html = sub_once(r'/\*__TJ_ROUTES__\*/null', lambda _: tj_routes, html, "tj routes json")
html = sub_once(r'/\*__TJ_MAP__\*/""', lambda _: _json.dumps(tj_map), html, "tj map svg")
# Tianjin logo: the verified early red roundel (same file the
# upcoming-cities directory uses, web/upcoming-logos/tianjin.b64) —
# substitute only when the file appears, mirroring the SJZ pattern.
tj_logo_path = BASE / "tianjin" / "logo.b64"
if tj_logo_path.exists():
    tj_logo_b64 = tj_logo_path.read_text(encoding="utf-8").strip()
    html = sub_once(r"/\*__TJ_LOGO__\*/''", lambda _: "'data:image/png;base64," + tj_logo_b64 + "'", html, "tj logo")
else:
    print("WARNING: web/tianjin/logo.b64 missing; Tianjin logo will be empty")
tj_splash_path = BASE / "tianjin" / "splash.b64"
if tj_splash_path.exists():
    tj_splash_b64 = tj_splash_path.read_text(encoding="utf-8").strip()
    html = sub_once(r'/\*__TJ_SPLASH__\*/', lambda _: tj_splash_b64, html, "tj splash")
else:
    print("WARNING: web/tianjin/splash.b64 missing; Tianjin splash will be empty")
tj_splash_dark_path = BASE / "tianjin" / "splash-dark.b64"
if tj_splash_dark_path.exists():
    tj_splash_dark_b64 = tj_splash_dark_path.read_text(encoding="utf-8").strip()
    html = sub_once(r'/\*__TJ_SPLASH_DARK__\*/', lambda _: tj_splash_dark_b64, html, "tj splash dark")
else:
    print("WARNING: web/tianjin/splash-dark.b64 missing; Tianjin dark splash will be empty")

# S11. inline the Wuxi Metro data (5 operating lines, 89 stations,
# 26E116). Same pattern: precomputed stations/routes from the RMP
# Gallery map v26, station order triple-cross-checked (the RMP
# drawing's S1 order at 江阴中医院/江阴高铁站 is WRONG — the package
# follows Wikipedia + Wikidata latitude order). NOT in the data
# files: 安镇 (Line 2, unopened), 霞客湾科学城 (S1, built but
# unopened) and Line 4 Phase 2 (not open). S1 is its own line key
# sharing 堰桥 with Line 1 (through-running in reality), coloured
# with Line 1 red per the official palette.
wx_stations = (BASE / "wuxi" / "stations.json").read_text(encoding="utf-8")
wx_routes = (BASE / "wuxi" / "routes.json").read_text(encoding="utf-8")
wx_map = (BASE / "wuxi" / "map.svg").read_text(encoding="utf-8")
assert "</script" not in wx_stations, "wx stations json must not contain </script"
assert "</script" not in wx_routes, "wx routes json must not contain </script"
assert "</script" not in wx_map, "wx map svg must not contain </script"
html = sub_once(r'/\*__WX_STATIONS__\*/\[\]', lambda _: wx_stations, html, "wx stations json")
html = sub_once(r'/\*__WX_ROUTES__\*/null', lambda _: wx_routes, html, "wx routes json")
html = sub_once(r'/\*__WX_MAP__\*/""', lambda _: _json.dumps(wx_map), html, "wx map svg")
wx_logo_path = BASE / "wuxi" / "logo.b64"
if wx_logo_path.exists():
    wx_logo_b64 = wx_logo_path.read_text(encoding="utf-8").strip()
    html = sub_once(r"/\*__WX_LOGO__\*/''", lambda _: "'data:image/png;base64," + wx_logo_b64 + "'", html, "wx logo")
else:
    print("WARNING: web/wuxi/logo.b64 missing; Wuxi logo will be empty")
# 26E117: small-slot mark for Wuxi — the red symbol cropped out of the
# official lockup (crop only, artwork untouched; the full lockup above
# stays for large placements like the splash). The horizontal lockup
# shrank to illegibility in the 23-26px circular slots and its black
# text vanished on dark backgrounds; the symbol alone reads clearly
# at any size in both appearances.
wx_mark_path = BASE / "wuxi" / "logo-mark.b64"
if wx_mark_path.exists():
    wx_mark_b64 = wx_mark_path.read_text(encoding="utf-8").strip()
    html = sub_once(r"/\*__WX_MARK__\*/''", lambda _: "'data:image/png;base64," + wx_mark_b64 + "'", html, "wx mark")
else:
    print("WARNING: web/wuxi/logo-mark.b64 missing; Wuxi small-slot logo falls back to the lockup")
wx_splash_path = BASE / "wuxi" / "splash.b64"
if wx_splash_path.exists():
    wx_splash_b64 = wx_splash_path.read_text(encoding="utf-8").strip()
    html = sub_once(r'/\*__WX_SPLASH__\*/', lambda _: wx_splash_b64, html, "wx splash")
else:
    print("WARNING: web/wuxi/splash.b64 missing; Wuxi splash will be empty")
wx_splash_dark_path = BASE / "wuxi" / "splash-dark.b64"
if wx_splash_dark_path.exists():
    wx_splash_dark_b64 = wx_splash_dark_path.read_text(encoding="utf-8").strip()
    html = sub_once(r'/\*__WX_SPLASH_DARK__\*/', lambda _: wx_splash_dark_b64, html, "wx splash dark")
else:
    print("WARNING: web/wuxi/splash-dark.b64 missing; Wuxi dark splash will be empty")

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
sjz_tt_path = BASE / "timetable" / "sjz.json"
sjz_tt = sjz_tt_path.read_text(encoding="utf-8") if sjz_tt_path.exists() else "{}"
tj_tt_path = BASE / "timetable" / "tj.json"
tj_tt = tj_tt_path.read_text(encoding="utf-8") if tj_tt_path.exists() else "{}"
wx_tt_path = BASE / "timetable" / "wx.json"
wx_tt = wx_tt_path.read_text(encoding="utf-8") if wx_tt_path.exists() else "{}"
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
assert "</script" not in sjz_tt, "sjz timetable json must not contain </script"
assert "</script" not in tj_tt, "tj timetable json must not contain </script"
assert "</script" not in wx_tt, "wx timetable json must not contain </script"
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
html = sub_once(r'/\*__SJZ_TIMETABLE__\*/\{\}', lambda _: sjz_tt, html, "sjz timetable json")
html = sub_once(r'/\*__TJ_TIMETABLE__\*/\{\}', lambda _: tj_tt, html, "tj timetable json")
html = sub_once(r'/\*__WX_TIMETABLE__\*/\{\}', lambda _: wx_tt, html, "wx timetable json")
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
sjz_ll = (BASE / "latlng" / "latlng-sjz.json").read_text(encoding="utf-8")
tj_ll = (BASE / "latlng" / "latlng-tj.json").read_text(encoding="utf-8")
wx_ll = (BASE / "latlng" / "latlng-wx.json").read_text(encoding="utf-8")
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
assert "</script" not in sjz_ll, "sjz latlng json must not contain </script"
assert "</script" not in tj_ll, "tj latlng json must not contain </script"
assert "</script" not in wx_ll, "wx latlng json must not contain </script"
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
html = sub_once(r'/\*__SJZ_LATLNG__\*/\{\}', lambda _: sjz_ll, html, "sjz latlng json")
html = sub_once(r'/\*__TJ_LATLNG__\*/\{\}', lambda _: tj_ll, html, "tj latlng json")
html = sub_once(r'/\*__WX_LATLNG__\*/\{\}', lambda _: wx_ll, html, "wx latlng json")

# S8. inline the verified official metro logos for the not-yet-
# supported cities (web/upcoming-logos/, see its MANIFEST.md): the
# Settings "即将支持" rows show the real logo instead of the generic
# grey M icon. Only visually verified files are listed. Cities
# without a verified logo keep the M icon. 26E109: 18 more cities
# cut from the user's own logo-collage photo (same method as the
# main line's collage pass: per-cell crop, white background
# flood-filled to transparency, artwork untouched, no city-name
# text) — including Tianjin, whose collage glyph is the same red
# roundel as the previously held-back Wikimedia file.
_SOON_LOGO_FILES = {
    "广州": "guangzhou.b64", "南京": "nanjing.b64", "西安": "xian.b64",
    "杭州": "hangzhou.b64", "长沙": "changsha.b64", "无锡": "wuxi.b64",
    "南昌": "nanchang.b64", "福州": "fuzhou.b64", "南宁": "nanning.b64",
    "温州": "wenzhou.b64", "济南": "jinan.b64", "徐州": "xuzhou.b64",
    "天津": "tianjin.b64", "太原": "taiyuan.b64", "呼和浩特": "huhehaote.b64",
    "苏州": "suzhou.b64", "南通": "nantong.b64", "宁波": "ningbo.b64",
    "绍兴": "shaoxing.b64", "合肥": "hefei.b64", "厦门": "xiamen.b64",
    "郑州": "zhengzhou.b64", "洛阳": "luoyang.b64", "武汉": "wuhan.b64",
    "佛山": "foshan.b64", "东莞": "dongguan.b64", "贵阳": "guiyang.b64",
    "昆明": "kunming.b64", "兰州": "lanzhou.b64", "乌鲁木齐": "wulumuqi.b64",
    "雄安": "xiongan.b64",
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

# T2. inline the trains seed (web/trains.json): the 12-city train list for
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
