#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/package_app.sh [--clean]

Builds TabApp in release mode and scaffolds a macOS .app bundle in dist/.

Environment overrides:
  APP_NAME      (default: WindNav)
  BUNDLE_ID     (default: com.windnav.app)
  VERSION       (default: 1.0.0)
  BUILD_NUMBER  (default: 1)
EOF
}

CLEAN_DIST=0
while (($# > 0)); do
  case "$1" in
    --clean)
      CLEAN_DIST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="${APP_NAME:-WindNav}"
BUNDLE_ID="${BUNDLE_ID:-com.windnav.app}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

ICON_SRC="${ROOT_DIR}/Packaging/AppIcon.icns"
BUILD_DIR="${ROOT_DIR}/.build"
BIN_SRC="${ROOT_DIR}/.build/release/TabApp"
DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
BIN_DST="${MACOS_DIR}/${APP_NAME}"
ICON_DST="${RESOURCES_DIR}/AppIcon.icns"
PLIST_PATH="${CONTENTS_DIR}/Info.plist"

if ! command -v swift >/dev/null 2>&1; then
  echo "Error: swift is required but was not found in PATH." >&2
  exit 1
fi

if [[ ! -f "${ICON_SRC}" ]]; then
  echo "Error: required icon not found at ${ICON_SRC}" >&2
  exit 1
fi

mkdir -p "${BUILD_DIR}"
if [[ ! -w "${BUILD_DIR}" ]]; then
  echo "Error: ${BUILD_DIR} is not writable." >&2
  exit 1
fi

cd "${ROOT_DIR}"
echo "Building release binary (TabApp)..."
swift build -c release --product TabApp

if [[ ! -x "${BIN_SRC}" ]]; then
  echo "Error: expected built executable at ${BIN_SRC}" >&2
  exit 1
fi

if ((CLEAN_DIST)); then
  echo "Cleaning dist directory..."
  rm -rf "${DIST_DIR}"
fi

# Replace target bundle safely on each run.
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_SRC}" "${BIN_DST}"
chmod +x "${BIN_DST}"
cp "${ICON_SRC}" "${ICON_DST}"

cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

echo "Validating Info.plist..."
plutil -lint "${PLIST_PATH}" >/dev/null

echo "App bundle ready: ${APP_BUNDLE}"