#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Hopbar"
VERSION="0.1.0"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG_ROOT="$ROOT/.build/dmg-root"
DMG="$DIST/$APP_NAME-$VERSION-preview.dmg"
VOLUME_NAME="$APP_NAME $VERSION"

if [[ ! -d "$APP" ]]; then
  "$ROOT/Scripts/package_app.sh"
fi

rm -rf "$DMG_ROOT" "$DMG"
mkdir -p "$DMG_ROOT"

ditto "$APP" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"

cat > "$DMG_ROOT/README.txt" <<'EOF'
Hopbar preview build

Drag Hopbar.app to Applications, then launch it from Applications.

This preview build is ad-hoc signed, not Apple Developer ID notarized.
If macOS blocks the first launch, use right-click -> Open.
EOF

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG"

codesign --force --sign - "$DMG"

echo "Created $DMG"
