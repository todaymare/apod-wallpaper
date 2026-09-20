#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

swift build -c release
RELEASE_BIN_DIR=$(swift build -c release --show-bin-path)

APP_DIR="$ROOT_DIR/build/APOD Wallpaper.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$RELEASE_BIN_DIR/APODWallpaper" "$APP_DIR/Contents/MacOS/APODWallpaper"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/APODWallpaper"

echo "Built $APP_DIR"
