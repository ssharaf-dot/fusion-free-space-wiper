#!/bin/bash
#
# build.sh — Build Fusion Free Space Wiper.app for Intel (x86_64) macOS 10.15+
# using ONLY the Command Line Tools (no full Xcode required), then package a DMG.
#
# Output:
#   build/FusionFreeSpaceWiper.app
#   dist/FusionFreeSpaceWiper-1.0.0.dmg
#
# This produces an x86_64 binary with a 10.15 (Catalina) deployment target that
# links against AppKit. It uses the OS-provided Swift 5 ABI-stable runtime that
# ships in macOS 10.14.4+ (so no Swift runtime needs bundling on Catalina).
#
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
APP_NAME="FusionFreeSpaceWiper"
DISPLAY_NAME="Fusion Free Space Wiper"
VERSION="1.1.0"
ARCH_TARGET="x86_64-apple-macosx10.15"

BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
APP="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
echo "==> SDK: $SDK"
echo "==> Target: $ARCH_TARGET"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR" "$DIST_DIR"

SOURCES=$(find "$ROOT/Sources/$APP_NAME" -name '*.swift' | sort)
echo "==> Compiling $(echo "$SOURCES" | wc -l | tr -d ' ') Swift files"

swiftc \
  -swift-version 5 \
  -O \
  -target "$ARCH_TARGET" \
  -sdk "$SDK" \
  -framework AppKit \
  -o "$MACOS_DIR/$APP_NAME" \
  $SOURCES

echo "==> Installing Info.plist"
cp "$ROOT/Sources/$APP_NAME/Resources/Info.plist" "$APP/Contents/Info.plist"

# Optional icon, if present.
if [ -f "$ROOT/Sources/$APP_NAME/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Sources/$APP_NAME/Resources/AppIcon.icns" "$RES_DIR/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

echo "==> Binary info"
file "$MACOS_DIR/$APP_NAME"
otool -l "$MACOS_DIR/$APP_NAME" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print; f=0}'

echo "==> Ad-hoc code signing (Gatekeeper on Catalina: right-click > Open on first launch)"
codesign --force --deep --sign - "$APP" || echo "WARN: codesign failed (app still runs after right-click > Open)"

echo "==> Building DMG"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo ""
echo "==> DONE"
echo "    App: $APP"
echo "    DMG: $DMG"
ls -lh "$DMG"
