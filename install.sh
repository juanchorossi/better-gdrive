#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Better GDrive"
SCHEME="BetterGDrive"
BUILD_DIR="$SCRIPT_DIR/.build"

echo "▸ Better GDrive — installer"
echo ""

# Kill any running instance
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
  echo "  Stopping running instance..."
  pkill -x "$APP_NAME" || true
  sleep 1
fi

# Rclone binary check
RCLONE_PATH="$SCRIPT_DIR/BetterGDrive/Resources/rclone"
if [[ ! -x "$RCLONE_PATH" ]]; then
  echo "  ✗ rclone binary not found at BetterGDrive/Resources/rclone"
  echo "    Download the macOS arm64 build from https://rclone.org/downloads/"
  echo "    and place it there, then re-run this script."
  exit 1
fi
echo "  ✓ rclone binary present ($(du -sh "$RCLONE_PATH" | cut -f1))"

# Regenerate Xcode project
echo "  Regenerating Xcode project..."
(cd "$SCRIPT_DIR" && xcodegen generate --quiet)
echo "  ✓ xcodegen done"

# Build
echo "  Building $APP_NAME (Debug)..."
xcodebuild \
  -project "$SCRIPT_DIR/BetterGDrive.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM=834JA84DX2 \
  build 2>&1 | grep -E "^(error:|warning:|Build succeeded|Build FAILED|✗)" || true

# Locate built app
BUILT_APP=$(find "$BUILD_DIR/Build/Products/Debug" -name "*.app" -maxdepth 1 | head -1)
if [[ -z "$BUILT_APP" ]]; then
  echo "  ✗ Build failed — app bundle not found."
  echo "    Run with verbose output: xcodebuild -scheme BetterGDrive -configuration Debug build"
  exit 1
fi
echo "  ✓ Build succeeded"

# Install to /Applications
DEST="/Applications/$APP_NAME.app"
echo "  Installing to $DEST..."
if [[ -d "$DEST" ]]; then
  rm -rf "$DEST"
fi
cp -R "$BUILT_APP" "$DEST"
echo "  ✓ Installed"

# Launch
echo ""
echo "  Launching $APP_NAME..."
open "$DEST"

echo ""
echo "Done. Better GDrive is running in the menu bar."
