#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Claude Usage Monitor"
BUNDLE_NAME="$APP_NAME.app"
BUILD_DIR=".build/release"
APP_DIR="$BUNDLE_NAME/Contents"

echo "=== Building ClaudeUsageMonitor ==="
swift build -c release 2>&1

echo "=== Creating .app bundle ==="
rm -rf "$BUNDLE_NAME"
mkdir -p "$APP_DIR/MacOS"

cp "$BUILD_DIR/ClaudeUsageMonitor" "$APP_DIR/MacOS/ClaudeUsageMonitor"
cp Info.plist "$APP_DIR/Info.plist"

echo "=== Done ==="
echo "App created at: $SCRIPT_DIR/$BUNDLE_NAME"
echo ""
echo "To install:"
echo "  cp -R \"$BUNDLE_NAME\" /Applications/"
