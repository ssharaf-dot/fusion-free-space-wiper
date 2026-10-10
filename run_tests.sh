#!/bin/bash
#
# run_tests.sh — Compile and run the engine test runner.
#
# By default it also creates a DISPOSABLE ~11 GiB sparse APFS disk image, mounts
# it, runs the integration tests against that image (never your startup disk),
# and then detaches and deletes it.
#
# Pass --no-image to run only the pure-logic unit tests.
#
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
# Tests run natively on the host arch (they exercise pure logic + real filesystem
# behavior); the shipping app is built separately for x86_64 by build.sh.
HOST_ARCH="$(uname -m)"
TARGET="${HOST_ARCH}-apple-macosx10.15"

BIN="$ROOT/build/ffsw-tests"
mkdir -p "$ROOT/build"

echo "==> Compiling test runner ($TARGET)"
swiftc -swift-version 5 -target "$TARGET" -sdk "$SDK" -O \
  -o "$BIN" \
  "$ROOT/Sources/FusionFreeSpaceWiper/Models/Models.swift" \
  "$ROOT/Sources/FusionFreeSpaceWiper/Engine/"*.swift \
  "$ROOT/Tests/main.swift"

USE_IMAGE=1
[ "${1:-}" = "--no-image" ] && USE_IMAGE=0

if [ "$USE_IMAGE" = "1" ]; then
  IMG="$(mktemp -d)/ffsw_test.sparseimage"
  VOL="FFSWTEST-$$"
  # Must exceed the 10 GiB reserve floor with headroom to spare so the engine has
  # writable space above the reserve. Sparse: only actually-written bytes consume
  # host disk, so this stays small (~a few hundred MB written during tests).
  echo "==> Creating disposable sparse APFS image (grows as used; ~14 GiB logical)"
  hdiutil create -size 14g -type SPARSE -fs APFS -volname "$VOL" "$IMG" >/dev/null
  MOUNT_OUTPUT="$(hdiutil attach "$IMG" -nobrowse -mountpoint "/tmp/$VOL")"
  MOUNT="/tmp/$VOL"
  echo "    mounted at $MOUNT"
  cleanup() {
    echo "==> Detaching and deleting disposable image"
    hdiutil detach "$MOUNT" >/dev/null 2>&1 || hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
    rm -f "$IMG" 2>/dev/null || true
  }
  trap cleanup EXIT
  export FFSW_TEST_MOUNT="$MOUNT"
fi

echo "==> Running tests"
set +e
"$BIN"
CODE=$?
set -e
echo "==> Test runner exit code: $CODE"
exit $CODE
