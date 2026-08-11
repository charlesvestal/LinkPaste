#!/usr/bin/env bash
#
# One-time setup: push the signing + notarization credentials into GitHub
# Actions secrets so the release workflow can sign builds.
#
# Run this yourself — it needs your keychain and touches real credentials.
# Nothing it reads is ever written to disk outside $TMPDIR, and the temporary
# .p12 is shredded on exit.
#
# Usage:
#   scripts/setup_ci_secrets.sh
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Charles Vestal (J4722B5MJW)}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${NOTARY_ISSUER_ID:-}"

echo "Repository: $REPO"
echo "Identity:   $IDENTITY"
echo

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# --- Developer ID certificate ------------------------------------------------
# Export the .p12 from Keychain Access rather than with `security export`:
# `security export -t identities` dumps EVERY code-signing identity in the
# keychain, so your Apple Development private keys would end up in a GitHub
# secret alongside the one key CI actually needs. Exporting the single
# "Developer ID Application" item by hand keeps the blast radius to one cert.
if [[ -z "${P12_PATH:-}" ]]; then
  cat <<'INSTRUCTIONS'
==> Export the signing certificate first:
      1. Open Keychain Access → login → My Certificates
      2. Right-click "Developer ID Application: …" → Export…
      3. Save as a .p12 and choose a password

    Then re-run with the path:
      P12_PATH=~/Desktop/DeveloperID.p12 scripts/setup_ci_secrets.sh
INSTRUCTIONS
  exit 1
fi

[[ -f "$P12_PATH" ]] || { echo "error: no .p12 at $P12_PATH" >&2; exit 1; }
read -rsp "==> Password you used when exporting $P12_PATH: " P12_PASSWORD
echo

# Fail now, loudly, rather than in CI with an opaque codesign error.
openssl pkcs12 -in "$P12_PATH" -passin "pass:$P12_PASSWORD" -nokeys -legacy >/dev/null 2>&1 \
  || openssl pkcs12 -in "$P12_PATH" -passin "pass:$P12_PASSWORD" -nokeys >/dev/null 2>&1 \
  || { echo "error: could not open the .p12 with that password" >&2; exit 1; }

echo "==> Uploading certificate secrets"
base64 -i "$P12_PATH" | gh secret set DEVELOPER_ID_CERT_P12 --repo "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set DEVELOPER_ID_CERT_PASSWORD --repo "$REPO"
printf '%s' "$IDENTITY" | gh secret set SIGN_IDENTITY --repo "$REPO"

# --- Notarization key --------------------------------------------------------
if [[ -z "$NOTARY_KEY_ID" ]]; then
  read -rp "==> App Store Connect key ID (e.g. from ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8): " NOTARY_KEY_ID
fi
if [[ -z "$NOTARY_ISSUER_ID" ]]; then
  read -rp "==> App Store Connect issuer UUID: " NOTARY_ISSUER_ID
fi

KEY_PATH="${NOTARY_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${NOTARY_KEY_ID}.p8}"
[[ -f "$KEY_PATH" ]] || { echo "error: key not found at $KEY_PATH" >&2; exit 1; }

echo "==> Uploading notarization secrets"
base64 -i "$KEY_PATH" | gh secret set NOTARY_KEY_P8 --repo "$REPO"
printf '%s' "$NOTARY_KEY_ID" | gh secret set NOTARY_KEY_ID --repo "$REPO"
printf '%s' "$NOTARY_ISSUER_ID" | gh secret set NOTARY_ISSUER_ID --repo "$REPO"

echo
echo "==> Done. Secrets set on $REPO:"
gh secret list --repo "$REPO"
echo
echo "Cut a release with:  git tag v0.1.0 && git push origin v0.1.0"
