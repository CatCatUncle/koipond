#!/bin/zsh
# Builds a universal (Apple Silicon + Intel), ad-hoc signed KoiPond.app.
# Usage: ./build-app.sh [output-dir]   (default: ./dist)
set -euo pipefail

cd "${0:A:h}"
OUT="${1:-dist}"
APP="$OUT/KoiPond.app"

for arch in arm64 x86_64; do
  nice -n 10 swift build -c release --arch "$arch" --build-path ".build/$arch"
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/KoiPond" \
  .build/arm64/release/KoiPond .build/x86_64/release/KoiPond
cp -R .build/arm64/release/KoiPond_KoiPond.bundle "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>KoiPond</string>
  <key>CFBundleIdentifier</key><string>io.github.catcatuncle.koipond</string>
  <key>CFBundleName</key><string>中秋赏鱼</string>
  <key>CFBundleDisplayName</key><string>中秋赏鱼</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.1</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>io.github.catcatuncle.koipond</string>
    <key>CFBundleURLSchemes</key><array><string>koipond</string></array>
  </dict></array>
</dict>
</plist>
PLIST

xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/KoiPond"
echo "built $APP"
