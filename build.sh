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
VERSION="2.0.0"
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

# --- Bundle PhotoRec / TestDisk (GPL, CGSecurity) for the Recovery suite ---
# Official Intel/Catalina build; integrity pinned by SHA-256. Cached in Vendor/.
TD_TARBALL="testdisk-7.2.mac_intel_x86_64.tar.bz2"
TD_URL="https://www.cgsecurity.org/$TD_TARBALL"
TD_SHA="05cfe47e4d0c5667ba218af83b81aa18ad1e4cbbedfcab334e6f770d53d59386"
VENDOR="$ROOT/Vendor"; mkdir -p "$VENDOR"
if [ ! -f "$VENDOR/$TD_TARBALL" ]; then
  echo "==> Fetching PhotoRec/TestDisk 7.2 (official)"
  curl -fsSL -o "$VENDOR/$TD_TARBALL" "$TD_URL"
fi
GOT_SHA="$(shasum -a 256 "$VENDOR/$TD_TARBALL" | awk '{print $1}')"
if [ "$GOT_SHA" != "$TD_SHA" ]; then
  echo "ERROR: PhotoRec tarball SHA-256 mismatch!"; echo "  expected $TD_SHA"; echo "  got      $GOT_SHA"; exit 1
fi
echo "==> Bundling PhotoRec/TestDisk (SHA-256 verified)"
REC_DIR="$RES_DIR/recovery"; mkdir -p "$REC_DIR"
TD_TMP="$(mktemp -d)"; tar xjf "$VENDOR/$TD_TARBALL" -C "$TD_TMP"
TD_SRC="$(find "$TD_TMP" -maxdepth 1 -type d -name 'testdisk-*' | head -1)"
for bin in photorec testdisk fidentify; do
  [ -f "$TD_SRC/$bin" ] && cp "$TD_SRC/$bin" "$REC_DIR/$bin" && chmod +x "$REC_DIR/$bin"
done
# GPL compliance: ship the tools' license/readme alongside them.
for doc in COPYING README.md AUTHORS THANKS; do
  [ -f "$TD_SRC/$doc" ] && cp "$TD_SRC/$doc" "$REC_DIR/$doc"
done
rm -rf "$TD_TMP"
echo "    bundled: $(ls "$REC_DIR" | tr '\n' ' ')"

echo "==> Ad-hoc code signing (Gatekeeper on Catalina: right-click > Open on first launch)"
# Sign the bundled Mach-O tools first, then the whole app.
for bin in photorec testdisk fidentify; do
  [ -f "$REC_DIR/$bin" ] && codesign --force --sign - "$REC_DIR/$bin" 2>/dev/null || true
done
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
