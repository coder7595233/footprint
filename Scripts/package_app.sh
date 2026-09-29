#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${FOOTPRINT_BUILD_ROOT:-${TMPDIR:-/tmp}/footprint-build}"
SWIFT_SCRATCH_PATH="${FOOTPRINT_SWIFT_SCRATCH_PATH:-$BUILD_ROOT/swiftpm-scratch}"
CLANG_MODULE_CACHE_PATH_VALUE="${FOOTPRINT_CLANG_MODULE_CACHE_PATH:-$BUILD_ROOT/clang-module-cache}"
BUILD_CONFIGURATION="${FOOTPRINT_BUILD_CONFIGURATION:-release}"
BUILD_SUBDIR="${BUILD_CONFIGURATION:l}"
APP_DIR="${FOOTPRINT_APP_DIR:-$HOME/Applications/Footprint.app}"
TEMP_PLIST="$(mktemp)"
TEMP_ICON_DIR="$(mktemp -d)"
TEMP_ICON="$TEMP_ICON_DIR/Footprint.png"
BUILD_VERSION="$(date +%Y%m%d%H%M%S)"
PACKAGE_MODE="${1:-self-contained}"
ACTIVE_DEVELOPER_DIR="$(xcode-select -p)"
PYTHON_RUNTIME_SOURCE="${FOOTPRINT_PYTHON_RUNTIME_SOURCE:-$ACTIVE_DEVELOPER_DIR/Library/Frameworks/Python3.framework/Versions/Current}"

cleanup() {
  rm -f "$TEMP_PLIST"
  rm -rf "$TEMP_ICON_DIR"
}
trap cleanup EXIT

mkdir -p "$BUILD_ROOT"
mkdir -p "$(dirname "$APP_DIR")"

case "$BUILD_SUBDIR" in
  debug|release)
    ;;
  *)
    echo "Unsupported build configuration: $BUILD_CONFIGURATION" >&2
    echo "Expected FOOTPRINT_BUILD_CONFIGURATION to be debug or release" >&2
    exit 1
    ;;
esac

if [[ "${FOOTPRINT_SKIP_TESTS:-0}" != "1" ]]; then
  echo "F17: kör testerna före bygget (FOOTPRINT_SKIP_TESTS=1 hoppar över)."
  env CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_PATH_VALUE" swift test --disable-sandbox --scratch-path "$SWIFT_SCRATCH_PATH"
fi

BUILD_DIR="$(env CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_PATH_VALUE" swift build -c "$BUILD_SUBDIR" --disable-sandbox --scratch-path "$SWIFT_SCRATCH_PATH" --show-bin-path)"
if [[ "${SKIP_SWIFT_BUILD:-0}" != "1" ]]; then
  # SwiftPM can retain resources deleted from the source tree in an existing
  # product bundle. Recreate the resource product before every packaged build.
  rm -rf "$BUILD_DIR/Footprint_Footprint.bundle"
  env CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_PATH_VALUE" swift build -c "$BUILD_SUBDIR" --disable-sandbox --scratch-path "$SWIFT_SCRATCH_PATH"
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

if [[ ! -x "$PYTHON_RUNTIME_SOURCE/bin/python3" || ! -f "$PYTHON_RUNTIME_SOURCE/Python3" ]]; then
  echo "A complete Python3.framework runtime is required to create a self-contained Footprint app." >&2
  echo "Expected it at: $PYTHON_RUNTIME_SOURCE" >&2
  echo "Install/select Xcode or Command Line Tools, or set FOOTPRINT_PYTHON_RUNTIME_SOURCE." >&2
  exit 1
fi

env CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_PATH_VALUE" swift "$ROOT_DIR/Scripts/generate_app_icon.swift" "$TEMP_ICON"

cp "$ROOT_DIR/Scripts/Footprint-Info.plist" "$TEMP_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$TEMP_PLIST"

case "$PACKAGE_MODE" in
  self-contained)
    /usr/libexec/PlistBuddy -c "Delete :FootprintBootstrapSourceFolderName" "$TEMP_PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :FootprintPackageMode self-contained" "$TEMP_PLIST"
    ;;
  *)
    echo "Unsupported package mode: $PACKAGE_MODE" >&2
    echo "Expected: self-contained" >&2
    exit 1
    ;;
esac

cp "$TEMP_PLIST" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
cp "$BUILD_DIR/Footprint" "$APP_DIR/Contents/MacOS/Footprint"
chmod +x "$APP_DIR/Contents/MacOS/Footprint"
# The release binary ships with a full symbol table (~33 MB); none of it
# is needed at runtime.
strip -Sx "$APP_DIR/Contents/MacOS/Footprint"
# The app finds its resource bundle in Contents/Resources itself
# (DataStoreBootstrap.supportScriptURL). A copy at the .app root, where
# SwiftPM's Bundle.module looks, makes codesign refuse the app.
ditto "$BUILD_DIR/Footprint_Footprint.bundle" "$APP_DIR/Contents/Resources/Footprint_Footprint.bundle"
ditto "$PYTHON_RUNTIME_SOURCE" "$APP_DIR/Contents/Resources/Python"

# The exporters are stdlib-only (json/zipfile/xml/argparse); drop the
# parts of the copied framework they can never touch (~14 MB).
setopt null_glob
PYTHON_DIR="$APP_DIR/Contents/Resources/Python"
rm -rf "$PYTHON_DIR/Headers" "$PYTHON_DIR/include" "$PYTHON_DIR/share"
rm -f "$PYTHON_DIR"/bin/2to3* "$PYTHON_DIR"/bin/pydoc* "$PYTHON_DIR"/bin/idle*
PYTHON_LIB_DIR="$(echo "$PYTHON_DIR"/lib/python3.*)"
if [[ -d "$PYTHON_LIB_DIR" ]]; then
  rm -rf "$PYTHON_LIB_DIR/test" \
         "$PYTHON_LIB_DIR/idlelib" \
         "$PYTHON_LIB_DIR/tkinter" \
         "$PYTHON_LIB_DIR/turtledemo" \
         "$PYTHON_LIB_DIR/ensurepip" \
         "$PYTHON_LIB_DIR/lib2to3" \
         "$PYTHON_LIB_DIR"/config-3.*
  rm -rf "$PYTHON_LIB_DIR"/site-packages/*
fi

cp -L "$PYTHON_RUNTIME_SOURCE/bin/python3" "$APP_DIR/Contents/Resources/Python/bin/python3-footprint"
chmod +x "$APP_DIR/Contents/Resources/Python/bin/python3-footprint"

# The trimmed interpreter must still cover everything the exporters import.
"$APP_DIR/Contents/Resources/Python/bin/python3-footprint" -c "import argparse, copy, json, pathlib, re, zipfile, xml.etree.ElementTree, xml.sax.saxutils" || {
  echo "Trimmed Python runtime is missing required stdlib modules." >&2
  exit 1
}

cp "$TEMP_ICON" "$APP_DIR/Contents/Resources/Footprint.png"

# A real .icns keeps Finder/Dock from falling back to the generic icon.
ICONSET_DIR="$TEMP_ICON_DIR/Footprint.iconset"
mkdir -p "$ICONSET_DIR"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$TEMP_ICON" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$TEMP_ICON" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/Footprint.icns"
xattr -cr "$APP_DIR" || true
touch "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
