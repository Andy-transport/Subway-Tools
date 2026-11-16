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
xcrun -sdk iphoneos swiftc -target arm64-apple-ios16.0 -O -parse-as-library \
  -framework UIKit -framework WebKit -Xlinker -weak_framework -Xlinker ActivityKit \
  -o build/Payload/Metro.app/Metro app/AppDelegate.swift app/LiveActivity/TripAttributes.swift

echo "== 2b. compile Live Activity widget extension =="
mkdir -p build/Payload/Metro.app/PlugIns/LiveActivityWidget.appex
xcrun -sdk iphoneos swiftc -target arm64-apple-ios16.1 -O -parse-as-library \
  -framework SwiftUI -framework WidgetKit -framework ActivityKit \
  -o build/Payload/Metro.app/PlugIns/LiveActivityWidget.appex/LiveActivityWidget \
  app/LiveActivity/TripAttributes.swift app/LiveActivity/LiveActivityWidget.swift
cp app/LiveActivity/LiveActivity-Info.plist build/Payload/Metro.app/PlugIns/LiveActivityWidget.appex/Info.plist

echo "== 3. bundle resources =="
cp app/Info.plist build/Payload/Metro.app/Info.plist
xcrun ibtool --compile build/Payload/Metro.app/LaunchScreen.storyboardc --sdk iphoneos app/LaunchScreen.storyboard
cp web/offline/index.html build/Payload/Metro.app/web/index.html
cp web/offline/vue.global.prod.js web/offline/hammer.min.js web/offline/svg-pan-zoom.js build/Payload/Metro.app/web/
cp web/offline/MTR2.8.0.pdf build/Payload/Metro.app/web/MTR2.8.0.pdf
python3 app/decode_icons.py build/Payload/Metro.app
python3 -c "import base64; open('build/Payload/Metro.app/Splash.png','wb').write(base64.b64decode(open('app/splash.b64').read()))"
# Native launch splash (build 53): the Shenyang + Shanghai per-city splash
# images, so the native splash view can show the right city's splash from
# launch (same images as the web per-city splash, inlined from these .b64).
python3 -c "import base64; open('build/Payload/Metro.app/SplashSY.jpg','wb').write(base64.b64decode(open('web/shenyang/splash.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/SplashSH.jpg','wb').write(base64.b64decode(open('web/shanghai/splash.b64').read()))"
# Harbin splash (user-supplied 哈尔滨/配线查询 image, web/harbin/splash.b64).
python3 -c "import base64; open('build/Payload/Metro.app/SplashHB.jpg','wb').write(base64.b64decode(open('web/harbin/splash.b64').read()))"
# Dalian splash (user-supplied 大连/配线查询 image, web/dalian/splash.b64).
python3 -c "import base64; open('build/Payload/Metro.app/SplashDL.jpg','wb').write(base64.b64decode(open('web/dalian/splash.b64').read()))"
cp app/BeijingLogo.png app/ShenyangLogo.png app/ShanghaiLogo.png build/Payload/Metro.app/
python3 -c "import base64; open('build/Payload/Metro.app/HarbinLogo.png','wb').write(base64.b64decode(open('web/harbin/logo.b64').read()))"
python3 -c "import base64; open('build/Payload/Metro.app/DalianLogo.png','wb').write(base64.b64decode(open('web/dalian/logo.b64').read()))"
python3 -c "import base64; [open('build/Payload/Metro.app/TimetableIcon' + s + '.png','wb').write(base64.b64decode(open('web/timetable-icon' + s + '.b64').read())) for s in ['', '@2x', '@3x']]"

echo "== 4. package IPA =="
cd build
zip -r -y Convenient-transportation-1.0.4-unsigned.ipa Payload
ls -l Convenient-transportation-1.0.4-unsigned.ipa
unzip -l Convenient-transportation-1.0.4-unsigned.ipa
