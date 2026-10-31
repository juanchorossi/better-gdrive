#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Better GDrive"
SCHEME="BetterGDrive"
BUILD_DIR="$SCRIPT_DIR/.build"
PRODUCTS="$BUILD_DIR/Build/Products/Debug"

echo "▸ Better GDrive — installer"
echo ""

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

# Build. Signing comes from project.yml (the source of truth), not from overrides here.
# Drop any previous bundle first: otherwise a failed build leaves the old one in place
# and the "app bundle found" check below would install stale code as if it had succeeded.
rm -rf "$PRODUCTS"/*.app
echo "  Building $APP_NAME (Debug)..."
BUILD_LOG="$(mktemp -t bettergdrive-build)"
set +e
xcodebuild \
  -project "$SCRIPT_DIR/BetterGDrive.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$BUILD_DIR" \
  build > "$BUILD_LOG" 2>&1
BUILD_STATUS=$?
set -e
# Compiler diagnostics look like "path:line:col: error: …"; xcodebuild ends with "** BUILD FAILED **".
grep -E "(^|: )(error|warning): |\*\* BUILD (FAILED|SUCCEEDED) \*\*" "$BUILD_LOG" | sed 's/^/    /' || true
if [[ $BUILD_STATUS -ne 0 ]]; then
  echo "  ✗ Build failed (xcodebuild exit $BUILD_STATUS). Full log: $BUILD_LOG"
  exit 1
fi
rm -f "$BUILD_LOG"

# Locate built app
BUILT_APP=""
if [[ -d "$PRODUCTS" ]]; then
  BUILT_APP="$(find "$PRODUCTS" -maxdepth 1 -name "*.app" -print -quit)"
fi
if [[ -z "$BUILT_APP" ]]; then
  echo "  ✗ Build reported success but no app bundle in $PRODUCTS"
  exit 1
fi
echo "  ✓ Build succeeded"

# Stop the running instance only now, with a good build in hand: a failed build must not
# leave the user without the app (and without sync) that was working before.
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
  echo "  Stopping running instance..."
  pkill -x "$APP_NAME" || true
  sleep 1
fi

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
