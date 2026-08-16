#!/usr/bin/env bash
#
# Regenerate docs/appcast.xml to include the just-published release.
#
# Sparkle's generate_appcast tool needs the actual .zip on disk (to hash and
# EdDSA-sign it), so we keep a small local archive of every shipped zip
# outside the repo — the appcast itself only needs the last few versions
# (generate_appcast prunes automatically), but signing needs the real bytes.
# Run this only after scripts/sign_notarize.sh and the GitHub release upload,
# so the download URL below actually resolves.
#
# Usage:
#   scripts/update_appcast.sh <version>
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/update_appcast.sh <version>}"
VERSION="${VERSION#v}"
TAG="v$VERSION"

ARCHIVE_DIR="${SPARKLE_ARCHIVE_DIR:-$HOME/.linkpaste-release-archive}"
ZIP="dist/LinkPaste-$VERSION.zip"
GENERATE_APPCAST="$(find .build/artifacts/sparkle -type f -name generate_appcast -path '*bin*' | head -1)"

[[ -f "$ZIP" ]] || { echo "error: $ZIP not found — run scripts/release.sh, not this script directly" >&2; exit 1; }
[[ -x "$GENERATE_APPCAST" ]] || { echo "error: generate_appcast not found — run 'swift package resolve' first" >&2; exit 1; }

mkdir -p "$ARCHIVE_DIR"
cp "$ZIP" "$ARCHIVE_DIR/"
[[ -f docs/appcast.xml ]] && cp docs/appcast.xml "$ARCHIVE_DIR/appcast.xml"

echo "==> Generating appcast for $TAG"
"$GENERATE_APPCAST" \
  --download-url-prefix "https://github.com/charlesvestal/LinkPaste/releases/download/$TAG/" \
  "$ARCHIVE_DIR"

cp "$ARCHIVE_DIR/appcast.xml" docs/appcast.xml
echo "==> docs/appcast.xml updated"
