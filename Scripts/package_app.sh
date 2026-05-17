#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Hopbar"
BUNDLE_ID="dev.hopbar.app"
VERSION="0.1.0"
BUILD="1"
CONFIGURATION="release"
BUILD_ROOT="$ROOT/.build/release-package"
APP="$BUILD_ROOT/$APP_NAME.app"
DIST="$ROOT/dist"
ICNS="$BUILD_ROOT/Hopbar.icns"

swift build -c "$CONFIGURATION"

rm -rf "$BUILD_ROOT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mkdir -p "$DIST"

swift Scripts/make_icon.swift Resources/PromptSquare.svg "$ICNS"

cp ".build/$CONFIGURATION/Hopbar" "$APP/Contents/MacOS/Hopbar"
cp Resources/PromptSquare.svg "$APP/Contents/Resources/PromptSquare.svg"
cp "$ICNS" "$APP/Contents/Resources/Hopbar.icns"

python3 - "$APP/Contents/Info.plist" "$BUNDLE_ID" "$VERSION" "$BUILD" <<'PY'
import plistlib
import sys
from pathlib import Path

info_path = Path(sys.argv[1])
bundle_id = sys.argv[2]
version = sys.argv[3]
build = sys.argv[4]

info = {
    "CFBundleDevelopmentRegion": "en",
    "CFBundleExecutable": "Hopbar",
    "CFBundleIconFile": "Hopbar",
    "CFBundleIdentifier": bundle_id,
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "Hopbar",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": build,
    "LSMinimumSystemVersion": "12.0",
    "LSUIElement": True,
    "NSAppleEventsUsageDescription": "Hopbar needs Automation permission to run commands in iTerm or Terminal from the menu bar. Terminal tab mode also uses System Events.",
}

info_path.parent.mkdir(parents=True, exist_ok=True)
with info_path.open("wb") as file:
    plistlib.dump(info, file, sort_keys=False)
PY

xattr -cr "$APP" || true
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

rm -rf "$DIST/$APP_NAME.app"
ditto "$APP" "$DIST/$APP_NAME.app"

echo "Created $DIST/$APP_NAME.app"
