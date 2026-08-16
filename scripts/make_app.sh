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

# Regenerated every build so the shipped icon always matches scripts/make_icon.swift
# rather than drifting from a stale committed binary.
echo "==> Generating icon"
swift scripts/make_icon.swift
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Compile the asset catalog too. An .icns alone gets containerized by macOS 26 —
# drawn shrunk inside a grey system plate. Declaring CFBundleIconName with a
# compiled Assets.car is what makes the icon render natively; actool emits both
# the .car and a partial plist carrying that key.
echo "==> Compiling asset catalog"
xcrun actool build/Assets.xcassets \
  --compile "$APP/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --app-icon AppIcon \
  --output-partial-info-plist build/icon-partial.plist \
  > /dev/null

# Merge actool's CFBundleIconName into the app's Info.plist.
ICON_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" build/icon-partial.plist 2>/dev/null || echo "")
if [[ -n "$ICON_NAME" ]]; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string $ICON_NAME" "$APP/Contents/Info.plist"
fi

for required in Resources/AppIcon.icns Resources/Assets.car; do
  [[ -e "$APP/Contents/$required" ]] || { echo "error: missing $required" >&2; exit 1; }
done

# Ad-hoc sign the assembled bundle (not just the loose binary) so it has a
# designated requirement bound to the bundle's Info.plist and resources.
# Without this, Accessibility grants don't reliably stick to local dev
# builds — the linker's bare ad-hoc signature on the Mach-O alone doesn't
# cover the bundle, so TCC can't consistently recognize it between launches.
# scripts/sign_notarize.sh replaces this with a real Developer ID signature
# for release builds; --force lets it do that without complaint.
echo "==> Ad-hoc signing (for local runs; release replaces this with Developer ID)"
codesign --force --deep --sign - "$APP"

# Confirm the binary really is universal — a silently single-arch release would
# only fail for the users who can't run it.
echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/LinkPasteApp")"
lipo -archs "$APP/Contents/MacOS/LinkPasteApp" | grep -q 'arm64' \
  || { echo "error: arm64 slice missing" >&2; exit 1; }
lipo -archs "$APP/Contents/MacOS/LinkPasteApp" | grep -q 'x86_64' \
  || { echo "error: x86_64 slice missing" >&2; exit 1; }

plutil -lint "$APP/Contents/Info.plist"
echo "==> Built $APP"
