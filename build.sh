#!/bin/bash
# Build the Metro IPA on a macOS GitHub Actions runner.
# 1. Assemble the offline web page (downloads map SVG/PDF/JS, inlines SVG)
# 2. Compile the Swift shell with swiftc (no signing -> unsigned IPA)
# 3. Assemble Payload/Metro.app and zip it as an IPA
set -e
cd "$(dirname "$0")"

echo "== 0. select Xcode (iOS SDK 27.3) =="
XCODE_273=$(ls -d /Applications/Xcode_27.3*.app 2>/dev/null | head -n 1)
if [ -n "$XCODE_273" ]; then
  echo "Selecting Xcode: $XCODE_273"
  sudo xcode-select -s "$XCODE_273" || echo "xcode-select failed; continuing with default Xcode"
else
  echo "Xcode 27.3 not found; using default Xcode"
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
xcrun -sdk iphoneos swiftc -target arm64-apple-ios16.0 -O -parse-as-library \
  -framework UIKit -framework WebKit \
  -o build/Payload/Metro.app/Metro app/AppDelegate.swift

echo "== 3. bundle resources =="
cp app/Info.plist build/Payload/Metro.app/Info.plist
xcrun ibtool --compile build/Payload/Metro.app/LaunchScreen.storyboardc --sdk iphoneos app/LaunchScreen.storyboard
cp web/offline/index.html build/Payload/Metro.app/web/index.html
cp web/offline/vue.global.prod.js web/offline/hammer.min.js web/offline/svg-pan-zoom.js build/Payload/Metro.app/web/
cp web/offline/MTR2.8.0.pdf build/Payload/Metro.app/web/MTR2.8.0.pdf
python3 app/decode_icons.py build/Payload/Metro.app
python3 -c "import base64; open('build/Payload/Metro.app/Splash.png','wb').write(base64.b64decode(open('app/splash.b64').read()))"

echo "== 4. package IPA =="
cd build
zip -r -y Beijing-Subway-motion-1.0.1-unsigned.ipa Payload
ls -l Beijing-Subway-motion-1.0.1-unsigned.ipa
unzip -l Beijing-Subway-motion-1.0.1-unsigned.ipa
