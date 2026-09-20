#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Better GDrive"
VERSION="1.0.0"
DMG_NAME="BetterGDrive-${VERSION}.dmg"
STAGING="$SCRIPT_DIR/.dmg-staging"
OUTPUT="$SCRIPT_DIR/$DMG_NAME"

echo "▸ Better GDrive — DMG builder"
echo ""

# Locate the app — prefer /Applications, fall back to build output
if [[ -d "/Applications/$APP_NAME.app" ]]; then
  APP_PATH="/Applications/$APP_NAME.app"
elif [[ -d "$SCRIPT_DIR/.build/Build/Products/Debug/$APP_NAME.app" ]]; then
  APP_PATH="$SCRIPT_DIR/.build/Build/Products/Debug/$APP_NAME.app"
else
  echo "  ✗ App not found. Run ./install.sh first."
  exit 1
fi
echo "  Using $APP_PATH"

# Staging
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# DMG
rm -f "$OUTPUT"
echo "  Creating DMG…"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$OUTPUT" > /dev/null

rm -rf "$STAGING"

SIZE=$(du -sh "$OUTPUT" | cut -f1)
echo "  ✓ $DMG_NAME ($SIZE)"
echo ""
echo "  Note: recipients may need to right-click → Open on first launch"
echo "  (Debug build — signed for development, not notarized)"
