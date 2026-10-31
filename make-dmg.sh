#!/usr/bin/env bash
set -euo pipefail

# Packages the installed /Applications/Better GDrive.app into a DMG.
# The version comes from the app bundle itself, so run install.sh first.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Better GDrive"
# Stage outside the repo: the repo lives in a folder the app itself syncs to Drive, and a
# staging dir appearing and vanishing mid-run made rclone report "directory not found".
STAGING="$(mktemp -d -t bettergdrive-dmg)"
trap 'rm -rf "$STAGING"' EXIT

echo "▸ Better GDrive — DMG builder"
echo ""

# Locate the app — prefer /Applications, fall back to the install.sh build dir or Xcode DerivedData
DERIVED=$(find ~/Library/Developer/Xcode/DerivedData -name "$APP_NAME.app" -path "*/Debug/*" 2>/dev/null | head -1)
if [[ -d "/Applications/$APP_NAME.app" ]]; then
  APP_PATH="/Applications/$APP_NAME.app"
elif [[ -d "$SCRIPT_DIR/.build/Build/Products/Debug/$APP_NAME.app" ]]; then
  APP_PATH="$SCRIPT_DIR/.build/Build/Products/Debug/$APP_NAME.app"
elif [[ -n "$DERIVED" && -d "$DERIVED" ]]; then
  APP_PATH="$DERIVED"
else
  echo "  ✗ App not found. Run ./install.sh first."
  exit 1
fi
echo "  Using $APP_PATH"

# Version: read from the bundle, and refuse to package a stale build
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
PROJECT_VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\([^"]*\)".*/\1/p' "$SCRIPT_DIR/project.yml" | head -1)
if [[ -n "$PROJECT_VERSION" && "$VERSION" != "$PROJECT_VERSION" ]]; then
  echo "  ✗ App is $VERSION but project.yml says $PROJECT_VERSION. Run ./install.sh to rebuild."
  exit 1
fi
DMG_NAME="BetterGDrive-${VERSION}.dmg"
OUTPUT="$SCRIPT_DIR/$DMG_NAME"
echo "  Version $VERSION"

# Staging
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# DMG. hdiutil's automatic size estimate is too tight once the bundle carries the
# ~88 MB rclone binary and fails with a bogus "No space left on device", so size
# the image explicitly: staging size + 50% headroom + 20 MB.
rm -f "$OUTPUT"
STAGING_MB=$(du -sm "$STAGING" | cut -f1)
IMAGE_MB=$(( STAGING_MB + STAGING_MB / 2 + 20 ))
echo "  Creating DMG (${IMAGE_MB} MB image)…"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  -size "${IMAGE_MB}m" \
  "$OUTPUT" > /dev/null

SIZE=$(du -sh "$OUTPUT" | cut -f1)
echo "  ✓ $DMG_NAME ($SIZE)"
echo ""
echo "  Note: recipients may need to right-click → Open on first launch"
echo "  (Debug build — signed for development, not notarized)"
