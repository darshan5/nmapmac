#!/bin/sh
# Builds nMapMac.app from the Swift package into ./build.
#   scripts/build-app.sh            release build
#   scripts/build-app.sh debug      debug build
set -eu

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/nMapMac.app"
VERSION="$(git -C "$ROOT" describe --tags --always 2>/dev/null || echo 0.1.0)"

cd "$ROOT"
swift build -c "$CONFIG" --product nMapMac
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/nMapMac" "$APP/Contents/MacOS/nMapMac"
cp -R "$BIN_DIR/nMapMac_NMapMacCore.bundle" "$APP/Contents/Resources/"

# App icon, rendered by scripts/make-icon.swift.
ICONSET="$ROOT/build/nMapMac.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
SRC="$ROOT/Resources/AppIcon.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/nMapMac.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>nMapMac</string>
  <key>CFBundleDisplayName</key><string>nMapMac</string>
  <key>CFBundleIdentifier</key><string>app.nmapmac.nMapMac</string>
  <key>CFBundleExecutable</key><string>nMapMac</string>
  <key>CFBundleIconFile</key><string>nMapMac</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSAppleEventsUsageDescription</key><string>nMapMac uses AppleScript to run Nmap with administrator privileges.</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Nmap XML Output</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSItemContentTypes</key><array><string>public.xml</string></array>
      <key>LSHandlerRank</key><string>Alternate</string>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP"
