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
# AppIntents.swift is compiled into the app too, so the 6 Siri Shortcuts
# (AppIntents.swift, user 2026-11-18) are in the binary and the
# AppShortcutsProvider is discovered. AppIntents exists on iOS 16.0+,
# so it is linked normally, not weak.
# Compile strategy (Siri round 6, 2026-11-21): back to the single
# compile+link invocation that built every shipped IPA (#84-#86).
# The round-5 per-file -primary-file batch compiles failed three
# runs in a row (#87 "cannot specify -o when generating multiple
# output files", #89 "filename AppDelegate.swift used twice", #90
# the #87 error again): with this invocation shape the driver warns
# "save unknown driver flag -primary-file as additional
# swift-frontend flag" — it forwards -primary-file to the frontend
# instead of honouring it, so the batch semantics never engage.
# Do not reintroduce -primary-file here.
# Const values: the metadata processor below needs a
# .swiftconstvalues for the App Intents declarations. Harvest one
# best-effort by compiling AppIntents.swift ALONE (single input, so
# -c -o is legal and no -primary-file is needed) into a throwaway
# object that is never linked; the real binary is compiled from all
# sources by the main invocation right after. Non-fatal on purpose:
# if the solo compile ever fails (e.g. AppIntents.swift gains
# references to other app types), the build continues without Siri
# metadata, exactly like builds #84-#86.
mkdir -p build/obj
# Const-extraction protocols list (committed at the repo root as
# Metro_const_extract_protocols.json): Xcode's build system passes
# this list to swiftc via -const-gather-protocols-list whenever
# SWIFT_EMIT_CONST_VALUE_PROTOCOLS is non-empty. Without it the
# harvest below emits NO .swiftconstvalues at all (experiments 1-3,
# 2026-11-21); with it plus the plain-AppIntent declarations the
# harvest produces the real 57 KB file the metadata step consumes.
SWIFT_SOURCES="app/AppDelegate.swift app/AppIntents.swift app/SearchConditionsViewController.swift app/AppearanceView.swift app/LanguageView.swift app/LiveActivity/TripAttributes.swift"
xcrun -sdk iphoneos swiftc -target arm64-apple-ios16.0 -O -parse-as-library -emit-const-values \
  -const-gather-protocols-list Metro_const_extract_protocols.json \
  -module-name Metro -c \
  -framework UIKit -framework WebKit -framework AppIntents -framework UserNotifications -Xlinker -weak_framework -Xlinker ActivityKit \
  app/AppIntents.swift -o build/obj/AppIntents-harvest.o \
  || echo "WARNING: AppIntents const-values harvest failed; continuing without Siri metadata"
ls -la build/obj/*.swiftconstvalues || echo "WARNING: no .swiftconstvalues produced"
xcrun -sdk iphoneos swiftc -target arm64-apple-ios16.0 -O -parse-as-library -emit-const-values \
  -module-name Metro \
  -framework UIKit -framework WebKit -framework AppIntents -framework UserNotifications -Xlinker -weak_framework -Xlinker ActivityKit \
  $SWIFT_SOURCES -o "build/Payload/Subway Tools.app/Subway Tools"
# The metadata processor locates the module's const values beside the
# binary (Xcode leaves them in the products dir during its run); copy
# any harvested file in for the extraction step; it is removed again
# before packaging (see the rm after the processors below).
find build/obj "build/Payload/Subway Tools.app" -name "*.swiftconstvalues" -exec cp {} "build/Payload/Subway Tools.app/" \; 2>/dev/null || true
ls "build/Payload/Subway Tools.app"/*.swiftconstvalues 2>/dev/null || echo "WARNING: no swiftconstvalues beside the binary"

echo "== 2a. App Intents metadata (Siri Shortcuts discovery) =="
# A raw swiftc build skips Xcode's AppIntents metadata extraction, so
# without this step iOS never registers SubwayToolsShortcuts and the
# Siri shortcuts do not exist on device (user 2026-11-19: still cannot
# use them). Non-fatal on purpose: failures show in the build log and
# the app still builds; the delivered IPA is checked for
# Metadata.appintents.
# Interface (proven 2026-11-21, experiment run #109: the processor
# printed 'Writing Metadata.appintents' and the bundle gained
# Metadata.appintents with version.json + extract.actionsdata):
# Xcode 27.2's appintentsmetadataprocessor does NOT scan directories
# and does NOT take --binary-file/--source-files; its USAGE takes two
# LIST FILES -- --source-file-list and --swift-const-vals-list -- plus
# --toolchain-dir/--sdk-root/--xcode-version. Assemble both lists with
# ABSOLUTE paths (one path per line): the source list is exactly
# SWIFT_SOURCES; the const-vals list is the solo harvest output first,
# plus any other .swiftconstvalues in build/obj, deduped.
ROOT="$PWD"
: > build/obj/e8-sources.txt
for src in $SWIFT_SOURCES; do echo "$ROOT/$src" >> build/obj/e8-sources.txt; done
: > build/obj/e8-constvals.txt
for f in build/obj/*harvest*.swiftconstvalues; do if [ -f "$f" ]; then echo "$ROOT/$f" >> build/obj/e8-constvals.txt; fi; done
for f in build/obj/*.swiftconstvalues; do if [ -f "$f" ]; then grep -qxF "$ROOT/$f" build/obj/e8-constvals.txt || echo "$ROOT/$f" >> build/obj/e8-constvals.txt; fi; done
echo "-- source-file-list (build/obj/e8-sources.txt) --"
cat build/obj/e8-sources.txt
echo "-- swift-const-vals-list (build/obj/e8-constvals.txt) --"
cat build/obj/e8-constvals.txt
# Toolchain dir = two levels up from the tool's bin dir
# (.../XcodeDefault.xctoolchain/usr/bin/<tool> -> .../XcodeDefault.xctoolchain).
TOOL_PATH=$(xcrun -f appintentsmetadataprocessor || true)
TOOLCHAIN_DIR=$(cd "$(dirname "$TOOL_PATH")/../.." 2>/dev/null && pwd || true)
SDK_ROOT=$(xcrun --sdk iphoneos --show-sdk-path)
XCODE_VERSION=$(xcodebuild -version | tail -1 | awk '{print $NF}')
echo "TOOLCHAIN_DIR: $TOOLCHAIN_DIR"
echo "SDK_ROOT: $SDK_ROOT"
echo "XCODE_VERSION: $XCODE_VERSION"
xcrun appintentsmetadataprocessor \
  --output "$ROOT/build/Payload/Subway Tools.app/Metadata.appintents" \
  --toolchain-dir "$TOOLCHAIN_DIR" \
  --module-name Metro \
  --sdk-root "$SDK_ROOT" \
  --xcode-version "$XCODE_VERSION" \
  --platform-family iOS \
  --deployment-target 16.0 \
  --target-triple arm64-apple-ios16.0 \
  --source-file-list "$ROOT/build/obj/e8-sources.txt" \
  --swift-const-vals-list "$ROOT/build/obj/e8-constvals.txt" \
  --force \
  || echo "WARNING: appintentsmetadataprocessor failed - Siri shortcuts will not register"
# NL training only tunes phrase recognition; shortcut registration comes
# from Metadata.appintents above. This processor requires
# --extracted-metadata-path (run #81 log: the old --metadata-file /
# --module-name / --bundle-identifier flags are unknown options to it).
mkdir -p build/nl-training-temp
xcrun appintentsnltrainingprocessor \
  --extracted-metadata-path "build/Payload/Subway Tools.app/Metadata.appintents" \
  --infoplist-path app/Info.plist \
  --temp-dir-path build/nl-training-temp \
  --output "build/Payload/Subway Tools.app/Metadata.appintents" \
  || echo "WARNING: appintentsnltrainingprocessor failed - Siri phrases will not train"
ls -la "build/Payload/Subway Tools.app/Metadata.appintents" || true
# The const-values file was build-time input for the extraction step
# only; it is not part of the app bundle Xcode would ship.
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
python3 -c "import base64; [open('build/Payload/Subway Tools.app/TimetableIcon' + s + '.png','wb').write(base64.b64decode(open('web/timetable-icon' + s + '.b64').read())) for s in ['', '@2x', '@3x']]"

echo "== 4. package IPA =="
cd build
# NOTE: the workflow's Upload IPA step (.github/workflows/build-ipa.yml on
# GitHub) expects build/Convenient-transportation-1.0.3-unsigned.ipa — keep
# this name in sync with it. (The workflow still says 1.0.3 even though the
# app is 1.0.4; the deliverable is renamed to
# Convenient-transportation-1.0.4-unsigned.ipa when handed to the user.)
zip -r -y Convenient-transportation-1.0.3-unsigned.ipa Payload
ls -l Convenient-transportation-1.0.3-unsigned.ipa
unzip -l Convenient-transportation-1.0.3-unsigned.ipa
