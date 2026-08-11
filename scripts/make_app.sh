#!/usr/bin/env bash
#
# Build LinkPaste.app from the SwiftPM executable.
#
# SwiftPM emits a bare Mach-O binary; macOS needs a bundle (Info.plist, the
# Contents/ tree) before it will show a menu bar item, honour LSUIElement, or let
# the app be signed and notarized. This script assembles that by hand — cheaper
# than maintaining an .xcodeproj for a five-file app.
#
# Usage:
#   scripts/make_app.sh [version]     # default version comes from the git tag
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.0.0)}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="dist/LinkPaste.app"

echo "==> Building LinkPaste $VERSION (build $BUILD)"

# Universal so the release runs on both Apple silicon and Intel, regardless of
# which runner architecture produced it.
swift build -c release --arch arm64 --arch x86_64

BINARY="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/LinkPasteApp"
[[ -f "$BINARY" ]] || { echo "error: binary not found at $BINARY" >&2; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/LinkPasteApp"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"

if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi

# Confirm the binary really is universal — a silently single-arch release would
# only fail for the users who can't run it.
echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/LinkPasteApp")"
lipo -archs "$APP/Contents/MacOS/LinkPasteApp" | grep -q 'arm64' \
  || { echo "error: arm64 slice missing" >&2; exit 1; }
lipo -archs "$APP/Contents/MacOS/LinkPasteApp" | grep -q 'x86_64' \
  || { echo "error: x86_64 slice missing" >&2; exit 1; }

plutil -lint "$APP/Contents/Info.plist"
echo "==> Built $APP"
