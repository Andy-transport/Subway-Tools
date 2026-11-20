#!/bin/bash
# Build the Metro IPA on a macOS GitHub Actions runner.
# 1. Assemble the offline web page (downloads map SVG/PDF/JS, inlines SVG)
# 2. Compile the Swift shell with swiftc (no signing -> unsigned IPA)
# 3. Assemble Payload/Metro.app and zip it as an IPA
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
mkdir -p build/Payload/Metro.app/web
# ActivityKit is weak-linked: it does not exist on iOS 16.0 (the app's
# deployment target), and every use is guarded `if #available(iOS 16.1, *)`.
# TripAttributes.swift is compiled into the app too, so AppDelegate can
# start/update the Live Activity.
# AppIntents.swift is compiled into the app too, so the 6 Siri Shortcuts
# (AppIntents.swift, user 2026-11-18) are in the binary and the
# AppShortcutsProvider is discovered. AppIntents exists on iOS 16.0+,
# so it is linked normally, not weak.
# Two-phase compile (Siri round 5, 2026-11-20; phase 1 fixed in
# round 5b after run #87 failed with "cannot specify -o when
# generating multiple output files"; round 5c after run #89 failed
# with "filename AppDelegate.swift used twice"): phase 1 compiles
# each source separately with -emit-const-values, phase 2 links.
# Rounds 1-4 passed -emit-const-values to a single compile+link
# invocation and the metadata processor still reported "No
# swiftconstvalues found" (run #86 log) — the driver only emits the
# .swiftconstvalues file in -c mode, exactly like Xcode's separate
# compile/link steps. The file lands next to the objects in
# build/obj. Phase 1 must compile the files one at a time (Xcode
# does the same per-file): a single -c invocation over all sources
# still emits a module-level .o (the -num-threads 0 whole-module
# artifact), and the driver refuses -o when a compile produces
# multiple outputs. Per-file, the driver counts -primary-file as an
# input file, so the primary file must NOT be repeated in the
# positional list (that is the run #89 duplicate-filename error);
# pass it once via -primary-file and the remaining files after it.
mkdir -p build/obj
SWIFT_SOURCES="app/AppDelegate.swift app/AppIntents.swift app/SearchConditionsViewController.swift app/AppearanceView.swift app/LanguageView.swift app/LiveActivity/TripAttributes.swift"
for src in $SWIFT_SOURCES; do
  obj="build/obj/$(basename "${src%.swift}").o"
  others=""
  for f in $SWIFT_SOURCES; do
    if [ "$f" != "$src" ]; then others="$others $f"; fi
  done
  xcrun -sdk iphoneos swiftc -target arm64-apple-ios16.0 -O -parse-as-library -emit-const-values \
    -module-name Metro -c \
    -framework UIKit -framework WebKit -framework AppIntents -framework UserNotifications -Xlinker -weak_framework -Xlinker ActivityKit \
    -primary-file "$src" $others -o "$obj"
done
ls -la build/obj/*.swiftconstvalues || echo "WARNING: no .swiftconstvalues produced"
xcrun -sdk iphoneos swiftc -target arm64-apple-ios16.0 \
  -framework UIKit -framework WebKit -framework AppIntents -framework UserNotifications -Xlinker -weak_framework -Xlinker ActivityKit \
  build/obj/*.o -o build/Payload/Metro.app/Metro
# The metadata processor locates the module's const values beside the
# binary (Xcode leaves them in the products dir during its run); copy
# it in for the extraction step and remove it before packaging.
cp build/obj/*.swiftconstvalues build/Payload/Metro.app/ 2>/dev/null || echo "WARNING: no swiftconstvalues to place beside the binary"

echo "== 2a. App Intents metadata (Siri Shortcuts discovery) =="
# A raw swiftc build skips Xcode's AppIntents metadata extraction, so
# without this step iOS never registers SubwayToolsShortcuts and the
# Siri shortcuts do not exist on device (user 2026-11-19: still cannot
# use them). Non-fatal on purpose: failures show in the build log and
# the app still builds; the delivered IPA is checked for
# Metadata.appintents.
xcrun appintentsmetadataprocessor \
  --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
  --module-name Metro \
  --platform-family iOS \
  --deployment-target 16.0 \
  --bundle-identifier com.andytransport.metro \
  --target-triple arm64-apple-ios16.0 \
  --xcode-version "$(xcodebuild -version | tail -1 | awk '{print $NF}')" \
  --sdk-root "$(xcrun -sdk iphoneos --show-sdk-path)" \
  --binary-file build/Payload/Metro.app/Metro \
  --source-files app/AppDelegate.swift app/AppIntents.swift app/SearchConditionsViewController.swift app/AppearanceView.swift app/LanguageView.swift app/LiveActivity/TripAttributes.swift \
  --output build/Payload/Metro.app/Metadata.appintents \
  || echo "WARNING: appintentsmetadataprocessor failed - Siri shortcuts will not register"
# NL training only tunes phrase recognition; shortcut registration comes
# from Metadata.appintents above. This processor requires
# --extracted-metadata-path (run #81 log: the old --metadata-file /
# --module-name / --bundle-identifier flags are unknown options to it).
mkdir -p build/nl-training-temp
xcrun appintentsnltrainingprocessor \
  --extracted-metadata-path build/Payload/Metro.app/Metadata.appintents \
  --infoplist-path app/Info.plist \
  --temp-dir-path build/nl-training-temp \
  --output build/Payload/Metro.app/Metadata.appintents \
  || echo "WARNING: appintentsnltrainingprocessor failed - Siri phrases will not train"
ls -la build/Payload/Metro.app/Metadata.appintents || true
# The const-values file was build-time input for the extraction step
# only; it is not part of the app bundle Xcode would ship.
rm -f build/Payload/Metro.app/*.swiftconstvalues

echo "== 2b. Live Activity widget extension REMOVED (user 2026-11-18) =="
# The Live Activity widget extension (LiveActivityWidget.appex) is
# skipped: 全能签 cannot sign an app that contains an app extension,
# so installs of 1.0.4 failed with "无法安装" while 1.0.3 (no extension)
# installed fine. The AppDelegate Live Activity code stays and fails
# silently without the extension (Activity.request() throws, caught),
# so the "开始行程" button simply does nothing. Re-enable this step
# if a signing method that handles extensions is used.

echo "== 3. bundle resources =="
cp app/Info.plist build/Payload/Metro.app/Info.plist
# Per-app language (iOS Settings > Subway tools > Language): the .lproj
# folders make iOS offer the language choice; CFBundleLocalizations lists them.
for _l in en zh-Hans zh-Hant; do cp -r "app/${_l}.lproj" build/Payload/Metro.app/; done
xcrun ibtool --compile build/Payload/Metro.app/LaunchScreen.storyboardc --sdk iphoneos app/LaunchScreen.storyboard
cp web/offline/index.html build/Payload/Metro.app/web/index.html
cp web/offline/vue.global.prod.js web/offline/hammer.min.js web/offline/svg-pan-zoom.js build/Payload/Metro.app/web/
cp web/offline/MTR2.8.0.pdf build/Payload/Metro.app/web/MTR2.8.0.pdf
python3 app/decode_icons.py build/Payload/Metro.app
python3 -c "import base64; open('build/Payload/Metro.app/Splash.png','wb').write(base64.b64decode(open('app/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/SplashDark.jpg','wb').write(base64.b64decode(open('app/splash-dark.b64').read()))"
# Native launch splash (build 53): the Shenyang + Shanghai per-city splash
# images, so the native splash view can show the right city's splash from
# launch (same images as the web per-city splash, inlined from these .b64).
python3 -c "import base64; open('build/Payload/Metro.app/SplashSY.jpg','wb').write(base64.b64decode(open('web/shenyang/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/SplashSYDark.jpg','wb').write(base64.b64decode(open('web/shenyang/splash-dark.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/SplashSH.jpg','wb').write(base64.b64decode(open('web/shanghai/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/SplashSHDark.jpg','wb').write(base64.b64decode(open('web/shanghai/splash-dark.b64').read()))"
# Harbin splash (user-supplied 哈尔滨/配线查询 image, web/harbin/splash.b64).
python3 -c "import base64; open('build/Payload/Metro.app/SplashHB.jpg','wb').write(base64.b64decode(open('web/harbin/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/SplashHBDark.jpg','wb').write(base64.b64decode(open('web/harbin/splash-dark.b64').read()))"
# Dalian splash (user-supplied 大连/配线查询 image, web/dalian/splash.b64).
python3 -c "import base64; open('build/Payload/Metro.app/SplashDL.jpg','wb').write(base64.b64decode(open('web/dalian/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/SplashDLDark.jpg','wb').write(base64.b64decode(open('web/dalian/splash-dark.b64').read()))"
# Jinhua splash (user-supplied real splash, web/jinhua/splash.b64).
python3 -c "import base64; open('build/Payload/Metro.app/SplashJH.jpg','wb').write(base64.b64decode(open('web/jinhua/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/SplashJHDark.jpg','wb').write(base64.b64decode(open('web/jinhua/splash-dark.b64').read()))"
# Changzhou splash (user-supplied real splash, web/changzhou/splash.b64).
python3 -c "import base64; open('build/Payload/Metro.app/SplashCZ.jpg','wb').write(base64.b64decode(open('web/changzhou/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/SplashCZDark.jpg','wb').write(base64.b64decode(open('web/changzhou/splash-dark.b64').read()))"
# Chongqing splash (user-supplied real splash, edited — TRACK LAYOUT LOOKUP removed).
python3 -c "import base64; open('build/Payload/Metro.app/SplashCQ.jpg','wb').write(base64.b64decode(open('web/chongqing/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/SplashCQDark.jpg','wb').write(base64.b64decode(open('web/chongqing/splash-dark.b64').read()))"
# Changchun splash (real user splash, web/changchun/splash.b64).
python3 -c "import base64; open('build/Payload/Metro.app/SplashCC.jpg','wb').write(base64.b64decode(open('web/changchun/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/SplashCCDark.jpg','wb').write(base64.b64decode(open('web/changchun/splash-dark.b64').read()))"
# Shenzhen splash (user-supplied real splash, web/shenzhen/splash.b64).
python3 -c "import base64; open('build/Payload/Metro.app/SplashSZ.jpg','wb').write(base64.b64decode(open('web/shenzhen/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/SplashSZDark.jpg','wb').write(base64.b64decode(open('web/shenzhen/splash-dark.b64').read()))"
# Chengdu splash (user-supplied real splash, web/chengdu/splash.b64).
python3 -c "import base64; open('build/Payload/Metro.app/SplashCD.jpg','wb').write(base64.b64decode(open('web/chengdu/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/SplashCDDark.jpg','wb').write(base64.b64decode(open('web/chengdu/splash-dark.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/SplashQD.jpg','wb').write(base64.b64decode(open('web/qingdao/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/SplashQDDark.jpg','wb').write(base64.b64decode(open('web/qingdao/splash-dark.b64').read()))"
cp app/BeijingLogo.png app/ShenyangLogo.png app/ShanghaiLogo.png build/Payload/Metro.app/
python3 -c "import base64; open('build/Payload/Metro.app/HarbinLogo.png','wb').write(base64.b64decode(open('web/harbin/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/DalianLogo.png','wb').write(base64.b64decode(open('web/dalian/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/JinhuaLogo.png','wb').write(base64.b64decode(open('web/jinhua/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/ChangzhouLogo.png','wb').write(base64.b64decode(open('web/changzhou/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/ChongqingLogo.png','wb').write(base64.b64decode(open('web/chongqing/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/ChangchunLogo.png','wb').write(base64.b64decode(open('web/changchun/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/ShenzhenLogo.png','wb').write(base64.b64decode(open('web/shenzhen/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/ChengduLogo.png','wb').write(base64.b64decode(open('web/chengdu/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/QingdaoLogo.png','wb').write(base64.b64decode(open('web/qingdao/logo.b64').read()))"
python3 -c "import base64; [open('build/Payload/Metro.app/TimetableIcon' + s + '.png','wb').write(base64.b64decode(open('web/timetable-icon' + s + '.b64').read())) for s in ['', '@2x', '@3x']]"

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
