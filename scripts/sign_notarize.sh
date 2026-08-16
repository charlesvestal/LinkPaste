#!/usr/bin/env bash
#
# Sign, notarize, and staple LinkPaste.app so it opens on any Mac without the
# "unidentified developer" wall.
#
# Local prereqs (one-time):
#   1. A "Developer ID Application" cert in the login keychain.
#   2. A stored notary credential profile:
#        xcrun notarytool store-credentials linkpaste \
#          --key ~/.appstoreconnect/private_keys/AuthKey_XXXX.p8 \
#          --key-id XXXX --issuer <ISSUER-UUID>
#
# In CI these come from secrets instead — see .github/workflows/release.yml,
# which calls this script with the same interface.
#
# Usage:
#   scripts/sign_notarize.sh              # sign -> notarize -> staple -> zip
#   scripts/sign_notarize.sh sign-only    # sign + verify, no Apple round-trip
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-full}"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Charles Vestal (J4722B5MJW)}"
PROFILE="${NOTARY_PROFILE:-linkpaste}"
ENTITLEMENTS="Resources/LinkPaste.entitlements"
APP="dist/LinkPaste.app"
ZIP="dist/LinkPaste.zip"

[[ -d "$APP" ]] || { echo "error: $APP not found — run scripts/make_app.sh first" >&2; exit 1; }

FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"

echo "==> Signing Sparkle.framework's nested components (hardened runtime + secure timestamp)"
# A bare `codesign` on the app bundle only signs the outer envelope — it does
# not reach into Sparkle.framework. Every embedded executable has to carry its
# own Developer ID signature with hardened runtime, or notarization rejects
# the whole submission. Sign inside-out: leaves before the tree that contains
# them, XPC services and the Updater.app before the framework itself.
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$FRAMEWORK/Versions/B/Autoupdate"
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$FRAMEWORK/Versions/B/Updater.app"
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$FRAMEWORK"
codesign --verify --strict --verbose=2 "$FRAMEWORK"

echo "==> Signing with Developer ID (hardened runtime + secure timestamp)"
# --options runtime is mandatory: the notary service rejects anything without
# the hardened runtime enabled. No --deep: the framework tree above is already
# signed piece by piece, and --deep's automatic re-signing doesn't reliably
# apply the right options to nested bundles.
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [[ "$MODE" == "sign-only" ]]; then
  echo "==> sign-only: done. (spctl will say 'rejected' until notarized — expected.)"
  spctl -a -vvv -t exec "$APP" 2>&1 || true
  exit 0
fi

echo "==> Zipping for notary submission"
rm -f "$ZIP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Submitting to Apple notary (this can take a few minutes)"
if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
  # CI path: explicit App Store Connect API key.
  xcrun notarytool submit "$ZIP" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" \
    --wait
else
  # Local path: stored keychain profile.
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
fi

echo "==> Stapling the ticket to the app"
# Staple so the app validates offline; without this a user with no network sees
# a Gatekeeper prompt on first launch.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Verifying Gatekeeper acceptance"
spctl -a -vvv -t exec "$APP"

echo "==> Repackaging the stapled app"
rm -f "$ZIP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Done: $ZIP"
