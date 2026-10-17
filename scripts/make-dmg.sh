#!/bin/sh
# Builds build/nMapMac.dmg: the release app plus an Applications shortcut,
# so it installs by dragging.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/nMapMac.app"
DMG="$ROOT/build/nMapMac.dmg"
STAGE="$ROOT/build/dmg"

"$ROOT/scripts/build-app.sh" release

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -quiet -volname "nMapMac" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"
echo "Built $DMG"
