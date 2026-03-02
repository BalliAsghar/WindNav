#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$#" -ne 0 ]]; then
    echo "error: build_app.sh takes no arguments." >&2
    echo "Run: ./scripts/build_app.sh" >&2
    exit 1
fi

BUNDLE_ID="com.windnav.app"
ICON_ICNS_PATH="$ROOT_DIR/Packaging/AppIcon.icns"
ICON_FILENAME="$(basename "$ICON_ICNS_PATH")"

if [[ ! -f "$ICON_ICNS_PATH" ]]; then
    echo "error: missing icon file: $ICON_ICNS_PATH" >&2
    exit 1
fi


PLIST_TEMPLATE="$ROOT_DIR/Packaging/Info.plist.template"
if [[ ! -f "$PLIST_TEMPLATE" ]]; then
    echo "error: missing Info.plist template: $PLIST_TEMPLATE" >&2
    exit 1
fi

cd "$ROOT_DIR"

echo "Building WindNav release binary..."
swift build -c release --product WindNav

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="$BIN_DIR/WindNav"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "error: release binary not found at $BIN_PATH" >&2
    exit 1
fi

APP_DIR="$ROOT_DIR/dist/WindNav.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/WindNav"
chmod +x "$MACOS_DIR/WindNav"

echo "Using packaged icon: $ICON_ICNS_PATH"
cp "$ICON_ICNS_PATH" "$RESOURCES_DIR/$ICON_FILENAME"

INFO_PLIST="$CONTENTS_DIR/Info.plist"
sed \
    -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
    -e "s|__ICON_FILE__|$ICON_FILENAME|g" \
    "$PLIST_TEMPLATE" > "$INFO_PLIST"


# Copy WindNav.app to Applications
APPS_DIR="/Applications"
if [[ -d "$APPS_DIR/WindNav.app" ]]; then
    echo "Removing existing app at $APPS_DIR/WindNav.app"
    rm -rf "$APPS_DIR/WindNav.app"
fi
echo "Copying WindNav.app to $APPS_DIR"
cp -R "$APP_DIR" "$APPS_DIR"
echo "Build complete! You can find WindNav.app in $APPS_DIR"
