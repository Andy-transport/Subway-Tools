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
# Siri experiment 4: write the const-extraction protocols list into the
# build dir. Xcode's build system passes this list to swiftc via
# -const-gather-protocols-list whenever SWIFT_EMIT_CONST_VALUE_PROTOCOLS
# is non-empty; experiment 3 showed the flag makes swiftc EMIT
# .swiftconstvalues (2-byte/empty for the old OpenURLIntent file).
cat > build/Metro_const_extract_protocols.json <<'EOF'
["AppIntent","AppEntity","AppEnum","AppShortcutsProvider","EntityQuery","EntityStringQuery","EnumerableEntityQuery","DynamicOptionsProvider","AppCollection","LiveActivityIntent"]
EOF
SWIFT_SOURCES="app/AppDelegate.swift app/AppIntents.swift app/SearchConditionsViewController.swift app/AppearanceView.swift app/LanguageView.swift app/LiveActivity/TripAttributes.swift"
xcrun -sdk iphoneos swiftc -target arm64-apple-ios16.0 -O -parse-as-library -emit-const-values \
  -const-gather-protocols-list build/Metro_const_extract_protocols.json \
  -module-name Metro -emit-module-path build/obj/Metro.swiftmodule -c \
  -framework UIKit -framework WebKit -framework AppIntents -framework UserNotifications -Xlinker -weak_framework -Xlinker ActivityKit \
  app/AppIntents.swift -o build/obj/AppIntents-harvest.o \
  || echo "WARNING: AppIntents const-values harvest failed; continuing without Siri metadata"
echo "== Siri experiment 6 =="
echo "-- E6: harvest now also emits the module file (-emit-module-path build/obj/Metro.swiftmodule) --"
ls -la build/obj/Metro.swiftmodule 2>/dev/null || echo "Metro.swiftmodule: ABSENT"
for f in build/obj/*.swiftconstvalues; do if [ -f "$f" ]; then echo "E6 harvest constvalues: $f = $(wc -c < "$f") bytes"; fi; done
echo "== Siri experiment 4 =="
echo "-- H1: solo-harvest const values (protocols list, restructured AppIntents.swift) --"
ls -la build/obj/*.swiftconstvalues || echo "WARNING: no .swiftconstvalues produced"
for f in build/obj/*.swiftconstvalues; do if [ -f "$f" ]; then echo "H1 size: $f = $(wc -c < "$f") bytes"; fi; done
xcrun -sdk iphoneos swiftc -target arm64-apple-ios16.0 -O -parse-as-library -emit-const-values \
  -const-gather-protocols-list build/Metro_const_extract_protocols.json \
  -module-name Metro \
  -framework UIKit -framework WebKit -framework AppIntents -framework UserNotifications -Xlinker -weak_framework -Xlinker ActivityKit \
  $SWIFT_SOURCES -o build/Payload/Metro.app/Metro
# The metadata processor locates the module's const values beside the
# binary (Xcode leaves them in the products dir during its run); copy
# any harvested file in for the extraction step; it is removed again
# before packaging (see the rm after the processors below).
# Siri experiment 4 staging: find EVERY .swiftconstvalues produced
# anywhere under build/, echo paths+sizes, and copy them into the obj
# dir, beside the Metro binary, and into the .app — all BEFORE the
# metadata processor runs in section 2a below. (Beside the binary and
# into the .app are the same directory here: the binary is
# build/Payload/Metro.app/Metro.)
echo "-- E4 staging: all .swiftconstvalues under build/ --"
find build -name "*.swiftconstvalues" | while read -r f; do echo "found: $f = $(wc -c < "$f") bytes"; done
find build -name "*.swiftconstvalues" -exec cp {} build/obj/ \; 2>/dev/null || true
find build -name "*.swiftconstvalues" -exec cp {} build/Payload/Metro.app/ \; 2>/dev/null || true
ls -la build/obj/*.swiftconstvalues build/Payload/Metro.app/*.swiftconstvalues 2>/dev/null || echo "WARNING: no swiftconstvalues staged"

echo "== Siri experiment 5: candidate names =="
# Siri experiment 5: experiment 4 proved the solo harvest emits a real
# (57 KB) .swiftconstvalues, but it is named after the harvest object
# (AppIntents-harvest.swiftconstvalues), which matches no source file —
# and appintentsmetadataprocessor still reported 'No swiftconstvalues
# found'. Hypothesis: the processor only recognises const values named
# after a SOURCE file (AppIntents.swiftconstvalues) or after the MODULE
# (Metro.swiftconstvalues). Stage the harvest content under all four
# candidate names/locations before section 2a runs.
E5_HARVEST=""
for f in build/obj/*harvest*.swiftconstvalues; do if [ -f "$f" ]; then E5_HARVEST="$f"; break; fi; done
if [ -z "$E5_HARVEST" ]; then for f in build/obj/*.swiftconstvalues; do if [ -f "$f" ]; then E5_HARVEST="$f"; break; fi; done; fi
if [ -n "$E5_HARVEST" ]; then
  echo "E5 harvest source: $E5_HARVEST = $(wc -c < "$E5_HARVEST") bytes"
  for dest in build/Payload/Metro.app/AppIntents.swiftconstvalues build/Payload/Metro.app/Metro.swiftconstvalues build/obj/AppIntents.swiftconstvalues build/obj/Metro.swiftconstvalues; do
    if [ "$E5_HARVEST" != "$dest" ]; then cp "$E5_HARVEST" "$dest" || true; fi
    echo "E5 staged: $dest = $(wc -c < "$dest") bytes"
  done
else
  echo "WARNING: no harvest .swiftconstvalues found for experiment 5"
fi

echo "== Siri experiment 7: processor forensics =="
# Siri experiment 7: experiments 4-6 proved the harvest emits a real
# 57,128-byte .swiftconstvalues, yet appintentsmetadataprocessor still
# reports 'No swiftconstvalues found' under every filename, location,
# cwd, and with/without an emitted Metro.swiftmodule. Stop guessing:
# dump the tool's own --help text and the path/format strings compiled
# into its binary so the next step is based on what the tool actually
# expects. Everything here is diagnostic only and non-fatal.
TOOL=$(xcrun -f appintentsmetadataprocessor || true); echo "E7 tool: $TOOL"
xcrun appintentsmetadataprocessor --help 2>&1 || true
xcrun appintentsmetadataprocessor --version 2>&1 || true
if [ -n "$TOOL" ]; then strings "$TOOL" | grep -n -i -C 3 'swiftconstvalues' || true; fi
echo "-- E7 flag-like strings --"
if [ -n "$TOOL" ]; then strings "$TOOL" | grep -E '^--[a-z]' | sort -u || true; fi
echo "-- E7 path-like strings --"
if [ -n "$TOOL" ]; then strings "$TOOL" | grep -iE 'objects-normal|deriveddata|intermediates|\.appintents|metadata' | head -60 || true; fi

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
echo "-- E4 result: Metadata.appintents --"
ls -la build/Payload/Metro.app/Metadata.appintents 2>/dev/null || echo "Metadata.appintents: ABSENT"

echo "== Siri experiment 6: processor cwd matrix =="
# Siri experiment 6: exp5 ruled out filename/location in build/obj and
# the .app. Remaining hypotheses: appintentsmetadataprocessor locates
# the module's const values (a) relative to the compiled .swiftmodule —
# the harvest now emits build/obj/Metro.swiftmodule, so the standard
# invocation above (P1, cwd=root) doubles as the swiftmodule test —
# and/or (b) relative to its working directory. P2/P3 rerun the
# IDENTICAL processor command from different working directories, each
# writing to its own output path under build/exp6/ so the results are
# distinguishable. All paths in the reruns are absolute because the cwd
# changes. This block runs BEFORE the rm of the staged .swiftconstvalues
# below, so the reruns see the same staged inputs as P1.
ROOT="$PWD"
mkdir -p build/exp6
echo "-- E6 P2 (cwd=build/obj) --"
( cd build/obj && xcrun appintentsmetadataprocessor \
  --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
  --module-name Metro \
  --platform-family iOS \
  --deployment-target 16.0 \
  --bundle-identifier com.andytransport.metro \
  --target-triple arm64-apple-ios16.0 \
  --xcode-version "$(xcodebuild -version | tail -1 | awk '{print $NF}')" \
  --sdk-root "$(xcrun -sdk iphoneos --show-sdk-path)" \
  --binary-file "$ROOT/build/Payload/Metro.app/Metro" \
  --source-files "$ROOT/app/AppDelegate.swift" "$ROOT/app/AppIntents.swift" "$ROOT/app/SearchConditionsViewController.swift" "$ROOT/app/AppearanceView.swift" "$ROOT/app/LanguageView.swift" "$ROOT/app/LiveActivity/TripAttributes.swift" \
  --output "$ROOT/build/exp6/P2.appintents" ) || true
ls -la build/exp6/P2.appintents 2>/dev/null || echo "P2.appintents: ABSENT"
echo "-- E6 P3 (cwd=build/Payload/Metro.app) --"
( cd build/Payload/Metro.app && xcrun appintentsmetadataprocessor \
  --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
  --module-name Metro \
  --platform-family iOS \
  --deployment-target 16.0 \
  --bundle-identifier com.andytransport.metro \
  --target-triple arm64-apple-ios16.0 \
  --xcode-version "$(xcodebuild -version | tail -1 | awk '{print $NF}')" \
  --sdk-root "$(xcrun -sdk iphoneos --show-sdk-path)" \
  --binary-file "$ROOT/build/Payload/Metro.app/Metro" \
  --source-files "$ROOT/app/AppDelegate.swift" "$ROOT/app/AppIntents.swift" "$ROOT/app/SearchConditionsViewController.swift" "$ROOT/app/AppearanceView.swift" "$ROOT/app/LanguageView.swift" "$ROOT/app/LiveActivity/TripAttributes.swift" \
  --output "$ROOT/build/exp6/P3.appintents" ) || true
ls -la build/exp6/P3.appintents 2>/dev/null || echo "P3.appintents: ABSENT"
echo "-- E6 summary --"
e6_check() { if [ -e "$2" ]; then echo "E6 $1: EXISTS ($(du -sh "$2" 2>/dev/null | cut -f1)) — $2"; else echo "E6 $1: ABSENT — $2"; fi; }
e6_check "P1 standard (cwd=root, harvest emitted Metro.swiftmodule)" "build/Payload/Metro.app/Metadata.appintents"
e6_check "P2 (cwd=build/obj)" "build/exp6/P2.appintents"
e6_check "P3 (cwd=build/Payload/Metro.app)" "build/exp6/P3.appintents"
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
# Shijiazhuang splash (user-supplied real splash, web/shijiazhuang/splash.b64).
python3 -c "import base64; open('build/Payload/Metro.app/SplashSJZ.jpg','wb').write(base64.b64decode(open('web/shijiazhuang/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/SplashSJZDark.jpg','wb').write(base64.b64decode(open('web/shijiazhuang/splash-dark.b64').read()))"
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
