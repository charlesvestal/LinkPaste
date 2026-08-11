#!/usr/bin/env bash
#
# Cut a release: build, sign, notarize, staple, publish.
#
# This runs on YOUR Mac, not in CI — deliberately. Signing in GitHub Actions
# would mean exporting the Developer ID private key into repository secrets,
# where any job step (or any compromised third-party action) can read it. That
# key signs every product shipped under this identity, so a leak means revoking
# and reissuing the cert and re-signing everything. The convenience isn't worth
# it. CI builds and tests; your Mac signs.
#
# Prereqs (one-time):
#   1. A "Developer ID Application" cert in the login keychain.
#   2. A stored notary credential profile:
#        xcrun notarytool store-credentials linkpaste \
#          --key ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8 \
#          --key-id XXXXXXXXXX --issuer <ISSUER-UUID>
#
# Usage:
#   scripts/release.sh 0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>   e.g. scripts/release.sh 0.1.0}"
VERSION="${VERSION#v}"
TAG="v$VERSION"

# Refuse to ship uncommitted work — the tag would point at something that isn't
# what was actually built.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is dirty. Commit or stash first." >&2
  exit 1
fi

echo "==> Testing"
swift test

echo "==> Building $TAG"
scripts/make_app.sh "$VERSION"

echo "==> Signing and notarizing"
scripts/sign_notarize.sh

echo "==> Tagging $TAG"
git tag -a "$TAG" -m "$TAG"
git push origin "$TAG"

echo "==> Publishing release"
gh release create "$TAG" dist/LinkPaste.zip \
  --title "$TAG" \
  --generate-notes

echo "==> Done: $(gh release view "$TAG" --json url -q .url)"
