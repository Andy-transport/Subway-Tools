#!/bin/bash
# Build the Metro IPA on a macOS GitHub Actions runner.
# 1. Assemble the offline web page (downloads map SVG/PDF/JS, inlines SVG)
# 2. Compile the Swift shell with swiftc (no signing -> unsigned IPA)
# 3. Assemble Payload/Metro.app and zip it as an IPA
set -e
cd "$(dirname "$0")"

echo "== 0. select Xcode (iOS SDK 27.2) =="
echo "Installed Xcode versions:"
ls -d /Applications/Xcode*.app 2>/dev/null || echo "(none found)"
# Back to Xcode 27.2 (build 41): the SDK 27 launch crash is fixed by
# the Scene lifecycle migration (SceneDelegate owns the window), so
# SDK 27.2 is safe again. Fall back to Xcode 27.1, then 27.0.
XCODE_SEL=""
for v in 27.2 27.1 27.0; do
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
cp app/BeijingLogo.png app/ShenyangLogo.png app/ShanghaiLogo.png build/Payload/Metro.app/

echo "== 4. package IPA =="
cd build
zip -r -y Convenient-transportation-1.0.3-unsigned.ipa Payload
ls -l Convenient-transportation-1.0.3-unsigned.ipa
unzip -l Convenient-transportation-1.0.3-unsigned.ipa
