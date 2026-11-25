#!/bin/bash
# Build the Subway Tools IPA on a macOS GitHub Actions runner.
# 1. Assemble the offline web page (downloads map SVG/PDF/JS, inlines SVG)
# 2. Compile the Swift shell with swiftc (no signing -> unsigned IPA)
# 3. Assemble Payload/Subway Tools.app and zip it as an IPA
set -e
cd "$(dirname "$0")"

echo "== 0. select Xcode (prefer 27.3 beta, then 27.2/27.1/27.0) =="
echo "Installed Xcode versions:"
ls -d /Applications/Xcode*.app 2>/dev/null || echo "(none found)"
# Try Xcode 27.3 beta first (user request), then 27.2, 27.1, 27.0.
# The Scene lifecycle migration fixed the SDK 27 launch crash, so SDK 27.x is safe.
XCODE_SEL=""
for v in 27.3 27.2 27.1 27.0; do
  CAND=$(ls -d /Applications/Xcode_${v}*.app 2>/dev/null | head -n 1)
  if [ -n "$CAND" ]; then XCODE_SEL="$CAND"; break; fi
done
if [ -n "$XCODE_SEL" ]; then
  echo "Selecting Xcode: $XCODE_SEL"
  sudo xcode-select -s "$XCODE_SEL" || echo "xcode-select failed; continuing with default Xcode"
else
  echo "No Xcode 27.x found; using default Xcode"
fi
echo "Xcode version:"; xcodebuild -version
echo "iOS SDK version:"; xcrun -sdk iphoneos --show-sdk-version

echo "== 1. offline web page =="
cd web
python3 build_offline.py
cd ..

echo "== 2. compile Swift shell =="
rm -rf build
mkdir -p "build/Payload/Subway Tools.app/web"
# ActivityKit is weak-linked: it does not exist on iOS 16.0 (the app's
# deployment target), and every use is guarded `if #available(iOS 16.1, *)`.
# TripAttributes.swift is compiled into the app too, so AppDelegate can
# start/update the Live Activity.
# AppIntents.swift stays in the source list as an empty stub (26F128:
# Siri Shortcuts removed at the user's request — the intents, the
# provider, the const-values harvest and the metadata processors are
# all gone; nothing registers with Siri any more).
# Compile strategy (Siri round 6, 2026-11-21): the single
# compile+link invocation that built every shipped IPA (#84-#86).
# The round-5 per-file -primary-file batch compiles failed three
# runs in a row (#87 "cannot specify -o when generating multiple
# output files", #89 "filename AppDelegate.swift used twice", #90
# the #87 error again): with this invocation shape the driver warns
# "save unknown driver flag -primary-file as additional
# swift-frontend flag" — it forwards -primary-file to the frontend
# instead of honouring it, so the batch semantics never engage.
# Do not reintroduce -primary-file here.
mkdir -p build/obj
SWIFT_SOURCES="app/AppDelegate.swift app/AppIntents.swift app/SearchConditionsViewController.swift app/AppearanceView.swift app/LanguageView.swift app/LiveActivity/TripAttributes.swift"
xcrun -sdk iphoneos swiftc -target arm64-apple-ios16.0 -O -parse-as-library -emit-const-values \
  -module-name Metro \
  -framework UIKit -framework WebKit -framework AppIntents -framework UserNotifications -Xlinker -weak_framework -Xlinker ActivityKit \
  $SWIFT_SOURCES -o "build/Payload/Subway Tools.app/Subway Tools"
# Any .swiftconstvalues the main compile emitted beside the binary
# is build-time only (it fed the removed metadata step); never ship it.
rm -f "build/Payload/Subway Tools.app"/*.swiftconstvalues

echo "== 2b. Live Activity widget extension REMOVED (user 2026-11-18) =="
# The Live Activity widget extension (LiveActivityWidget.appex) is
# skipped: 全能签 cannot sign an app that contains an app extension,
# so installs of 1.0.4 failed with "无法安装" while 1.0.3 (no extension)
# installed fine. The AppDelegate Live Activity code stays and fails
# silently without the extension (Activity.request() throws, caught),
# so the "开始行程" button simply does nothing. Re-enable this step
# if a signing method that handles extensions is used.

echo "== 3. bundle resources =="
cp app/Info.plist "build/Payload/Subway Tools.app/Info.plist"
# Per-app language (iOS Settings > Subway tools > Language): the .lproj
# folders make iOS offer the language choice; CFBundleLocalizations lists them.
for _l in en zh-Hans zh-Hant; do cp -r "app/${_l}.lproj" "build/Payload/Subway Tools.app/"; done
xcrun ibtool --compile "build/Payload/Subway Tools.app/LaunchScreen.storyboardc" --sdk iphoneos app/LaunchScreen.storyboard
cp web/offline/index.html "build/Payload/Subway Tools.app/web/index.html"
cp web/offline/vue.global.prod.js web/offline/hammer.min.js web/offline/svg-pan-zoom.js "build/Payload/Subway Tools.app/web/"
cp web/offline/MTR2.8.0.pdf "build/Payload/Subway Tools.app/web/MTR2.8.0.pdf"
python3 app/decode_icons.py "build/Payload/Subway Tools.app"
python3 -c "import base64; open('build/Payload/Subway Tools.app/Splash.png','wb').write(base64.b64decode(open('app/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashDark.jpg','wb').write(base64.b64decode(open('app/splash-dark.b64').read()))"
# Universal launch splash (26D100): ONE pair for the whole app —
# user-supplied 'Subway Tools' posters, picked by dark/light only.
# The per-city posters below stay in the bundle, unreferenced, for a
# possible later re-enable.
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashST.jpg','wb').write(base64.b64decode(open('app/splash-st.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashSTDark.jpg','wb').write(base64.b64decode(open('app/splash-st-dark.b64').read()))"
# Same ST bytes under .png names (26D104): in this manually-assembled
# bundle UIImage(named:) demonstrably resolves .png-named files (city
# logos, TimetableIcon, Splash.png) but missed the .jpg-named ST pair on
# device, so every splash load fell back to the Beijing 'Splash' poster.
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashST.png','wb').write(base64.b64decode(open('app/splash-st.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashSTDark.png','wb').write(base64.b64decode(open('app/splash-st-dark.b64').read()))"
# Native launch splash (build 53): the Shenyang + Shanghai per-city splash
# images, so the native splash view can show the right city's splash from
# launch (same images as the web per-city splash, inlined from these .b64).
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashSY.jpg','wb').write(base64.b64decode(open('web/shenyang/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashSYDark.jpg','wb').write(base64.b64decode(open('web/shenyang/splash-dark.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashSH.jpg','wb').write(base64.b64decode(open('web/shanghai/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashSHDark.jpg','wb').write(base64.b64decode(open('web/shanghai/splash-dark.b64').read()))"
# Harbin splash (user-supplied 哈尔滨/配线查询 image, web/harbin/splash.b64).
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashHB.jpg','wb').write(base64.b64decode(open('web/harbin/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashHBDark.jpg','wb').write(base64.b64decode(open('web/harbin/splash-dark.b64').read()))"
# Dalian splash (user-supplied 大连/配线查询 image, web/dalian/splash.b64).
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashDL.jpg','wb').write(base64.b64decode(open('web/dalian/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashDLDark.jpg','wb').write(base64.b64decode(open('web/dalian/splash-dark.b64').read()))"
# Jinhua splash (user-supplied real splash, web/jinhua/splash.b64).
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashJH.jpg','wb').write(base64.b64decode(open('web/jinhua/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashJHDark.jpg','wb').write(base64.b64decode(open('web/jinhua/splash-dark.b64').read()))"
# Changzhou splash (user-supplied real splash, web/changzhou/splash.b64).
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashCZ.jpg','wb').write(base64.b64decode(open('web/changzhou/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashCZDark.jpg','wb').write(base64.b64decode(open('web/changzhou/splash-dark.b64').read()))"
# Chongqing splash (user-supplied real splash, edited — TRACK LAYOUT LOOKUP removed).
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashCQ.jpg','wb').write(base64.b64decode(open('web/chongqing/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashCQDark.jpg','wb').write(base64.b64decode(open('web/chongqing/splash-dark.b64').read()))"
# Changchun splash (real user splash, web/changchun/splash.b64).
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashCC.jpg','wb').write(base64.b64decode(open('web/changchun/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashCCDark.jpg','wb').write(base64.b64decode(open('web/changchun/splash-dark.b64').read()))"
# Shenzhen splash (user-supplied real splash, web/shenzhen/splash.b64).
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashSZ.jpg','wb').write(base64.b64decode(open('web/shenzhen/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashSZDark.jpg','wb').write(base64.b64decode(open('web/shenzhen/splash-dark.b64').read()))"
# Chengdu splash (user-supplied real splash, web/chengdu/splash.b64).
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashCD.jpg','wb').write(base64.b64decode(open('web/chengdu/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashCDDark.jpg','wb').write(base64.b64decode(open('web/chengdu/splash-dark.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashQD.jpg','wb').write(base64.b64decode(open('web/qingdao/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashQDDark.jpg','wb').write(base64.b64decode(open('web/qingdao/splash-dark.b64').read()))"
# Shijiazhuang splash (user-supplied real splash, web/shijiazhuang/splash.b64).
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashSJZ.jpg','wb').write(base64.b64decode(open('web/shijiazhuang/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashSJZDark.jpg','wb').write(base64.b64decode(open('web/shijiazhuang/splash-dark.b64').read()))"
# Tianjin / Wuxi splash posters (26E116, composed in the existing
# cities' poster style: city name + official logo + theme colour).
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashTJ.jpg','wb').write(base64.b64decode(open('web/tianjin/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashTJDark.jpg','wb').write(base64.b64decode(open('web/tianjin/splash-dark.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashWX.jpg','wb').write(base64.b64decode(open('web/wuxi/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/SplashWXDark.jpg','wb').write(base64.b64decode(open('web/wuxi/splash-dark.b64').read()))"
echo "== 3b. Siri data resources (26E113: same sources as the web pages) =="
# The query intents in AppIntents.swift answer from the app's own
# data. Bundle the SAME files the web pages inline — web/timetable/
# *.json (first/last trains; qd.json/sjz.json included since 26E113)
# and web/latlng/latlng-*.json (station coordinates) — copied
# verbatim, plus ONE derived index (city display names, line display
# names, station name lists) generated here from the same
# routes.json / stations.json sources. No hand-copied second dataset.
APP_ROOT="build/Payload/Subway Tools.app"
mkdir -p "$APP_ROOT/timetable" "$APP_ROOT/latlng"
for f in web/timetable/*.json; do cp "$f" "$APP_ROOT/timetable/"; done
for f in web/latlng/*.json; do cp "$f" "$APP_ROOT/latlng/"; done
python3 - <<'PYEOF'
import json, os
CITIES = [
    ("bj", "北京", "web"), ("sy", "沈阳", "web/shenyang"),
    ("sh", "上海", "web/shanghai"), ("hb", "哈尔滨", "web/harbin"),
    ("dl", "大连", "web/dalian"), ("jh", "金华", "web/jinhua"),
    ("cz", "常州", "web/changzhou"), ("cq", "重庆", "web/chongqing"),
    ("cc", "长春", "web/changchun"), ("sz", "深圳", "web/shenzhen"),
    ("cd", "成都", "web/chengdu"), ("qd", "青岛", "web/qingdao"),
    ("sjz", "石家庄", "web/shijiazhuang"),
    ("tj", "天津", "web/tianjin"), ("wx", "无锡", "web/wuxi"),
    ("ly", "洛阳", "web/luoyang"), ("gz", "广州", "web/guangzhou"),
    ("nj", "南京", "web/nanjing"),
    ("wh", "武汉", "web/wuhan"), ("hz", "杭州", "web/hangzhou"),
    ("zz", "郑州", "web/zhengzhou"),
]
def load(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)
index = {}
for key, name, folder in CITIES:
    routes = load(os.path.join(folder, "routes.json"))
    stations = load(os.path.join(folder, "stations.json"))
    lines = {k: (v.get("name") or k) for k, v in (routes.get("lines") or {}).items()}
    index[key] = {"name": name, "lines": lines, "stations": [s["n"] for s in stations]}
out = "build/Payload/Subway Tools.app/timetable/index.json"
with open(out, "w", encoding="utf-8") as f:
    json.dump(index, f, ensure_ascii=False)
print("wrote", out, "cities:", len(index))
PYEOF
ls "$APP_ROOT/timetable" | head -20

cp app/BeijingLogo.png app/ShenyangLogo.png app/ShanghaiLogo.png "build/Payload/Subway Tools.app/"
python3 -c "import base64; open('build/Payload/Subway Tools.app/HarbinLogo.png','wb').write(base64.b64decode(open('web/harbin/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/DalianLogo.png','wb').write(base64.b64decode(open('web/dalian/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/JinhuaLogo.png','wb').write(base64.b64decode(open('web/jinhua/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/ChangzhouLogo.png','wb').write(base64.b64decode(open('web/changzhou/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/ChongqingLogo.png','wb').write(base64.b64decode(open('web/chongqing/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/ChangchunLogo.png','wb').write(base64.b64decode(open('web/changchun/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/ShenzhenLogo.png','wb').write(base64.b64decode(open('web/shenzhen/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/ChengduLogo.png','wb').write(base64.b64decode(open('web/chengdu/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/QingdaoLogo.png','wb').write(base64.b64decode(open('web/qingdao/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/ShijiazhuangLogo.png','wb').write(base64.b64decode(open('web/shijiazhuang/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/TianjinLogo.png','wb').write(base64.b64decode(open('web/tianjin/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/WuxiLogo.png','wb').write(base64.b64decode(open('web/wuxi/logo-mark.b64').read()))" # 26E117: the native pill/menu slot is 26pt — use the cropped red symbol, not the full lockup (see web/build_offline.py)
python3 -c "import base64; open('build/Payload/Subway Tools.app/LuoyangLogo.png','wb').write(base64.b64decode(open('web/luoyang/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/GuangzhouLogo.png','wb').write(base64.b64decode(open('web/guangzhou/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/NanjingLogo.png','wb').write(base64.b64decode(open('web/nanjing/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/WuhanLogo.png','wb').write(base64.b64decode(open('web/wuhan/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/HangzhouLogo.png','wb').write(base64.b64decode(open('web/hangzhou/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Subway Tools.app/ZhengzhouLogo.png','wb').write(base64.b64decode(open('web/zhengzhou/logo.b64').read()))"
python3 -c "import base64; [open('build/Payload/Subway Tools.app/TimetableIcon' + s + '.png','wb').write(base64.b64decode(open('web/timetable-icon' + s + '.b64').read())) for s in ['', '@2x', '@3x']]"

echo "== 3a. app icon asset catalog (Assets.car, dark home-screen icon) =="
# The loose icon files decoded in step 3 carry ~dark variants, but iOS
# does not honour loose-file ~dark app icons in this hand-assembled
# bundle (26D109: on device the home-screen icon stayed on the light
# artwork even with the icon appearance set to Dark). The first-class
# mechanism is a compiled asset catalog: generate an
# AppIcon.appiconset (light + dark luminosity appearances) from the
# same app/icons.json source, compile it into Assets.car with actool,
# and merge actool's icon keys into the bundle's Info.plist (its
# CFBundleIcons replaces the hand-written one — same files, now
# catalog-backed; the loose files stay as fallback). FAIL LOUDLY on
# any problem: a failed build we can fix beats silently shipping the
# broken icon again.
APP_DIR="build/Payload/Subway Tools.app"
ICON_XCASSETS="build/Assets.xcassets"
ICON_PARTIAL="$PWD/build/icon-partial.plist"
rm -rf "$ICON_XCASSETS" "$ICON_PARTIAL"
python3 app/make_iconset.py "$ICON_XCASSETS"
ACTOOL="$(xcrun -f actool || true)"
if [ -z "$ACTOOL" ] || [ ! -x "$ACTOOL" ]; then
  echo "ERROR: actool not found (xcrun -f actool failed); cannot compile the app icon catalog" >&2
  exit 1
fi
"$ACTOOL" --compile "$APP_DIR" \
  --platform iphoneos \
  --minimum-deployment-target 16.0 \
  --target-device iphone --target-device ipad \
  --app-icon AppIcon \
  --output-partial-info-plist "$ICON_PARTIAL" \
  "$ICON_XCASSETS"
if [ ! -f "$APP_DIR/Assets.car" ]; then
  echo "ERROR: actool produced no Assets.car in $APP_DIR" >&2
  exit 1
fi
ls -l "$APP_DIR/Assets.car"
python3 - "$APP_DIR/Info.plist" "$ICON_PARTIAL" <<'PYEOF'
import plistlib, sys
app_plist_path, partial_path = sys.argv[1], sys.argv[2]
with open(partial_path, "rb") as f:
    partial = plistlib.load(f)
merged = {}
for key in ("CFBundleIcons", "CFBundleIcons~ipad", "CFBundleIconName"):
    if key in partial:
        merged[key] = partial[key]
primary = (merged.get("CFBundleIcons") or {}).get("CFBundlePrimaryIcon") or {}
if primary.get("CFBundleIconName") != "AppIcon":
    sys.exit("ERROR: actool partial plist lacks CFBundleIcons > CFBundlePrimaryIcon > CFBundleIconName == 'AppIcon': %r" % (partial,))
with open(app_plist_path, "rb") as f:
    app_plist = plistlib.load(f)
app_plist.update(merged)
with open(app_plist_path, "wb") as f:
    plistlib.dump(app_plist, f)
print("merged icon keys into the bundle Info.plist:", ", ".join(sorted(merged)))
PYEOF

echo "== 4. package IPA =="
cd build
# NOTE: the workflow's Upload IPA step (.github/workflows/build-ipa.yml on
# GitHub) uploads artifact 'Subway Tools' from build/Subway Tools.ipa
# (test/structure branch: package name is the plain app name, matching the
# test-branch workflow path) — keep this name in sync with it.
zip -r -y "Subway Tools.ipa" Payload
ls -l "Subway Tools.ipa"
unzip -l "Subway Tools.ipa"
