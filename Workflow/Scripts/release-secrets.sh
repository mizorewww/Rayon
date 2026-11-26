#!/bin/bash

# Give the repository on GitHub what its Release workflow signs and notarizes
# with. Run it yourself: it asks for passwords and uploads a private key.
#
# Usage:
#   bash Workflow/Scripts/release-secrets.sh <DeveloperID.p12> [AuthKey_<id>.p8] [Rayon.provisionprofile]
#
# The .p12: in Keychain Access, under My Certificates, select "Developer ID
# Application: …", File → Export Items…, and give it a password.
#
# For the notary service, either
#   - an App Store Connect API key: appstoreconnect.apple.com → Users and
#     Access → Integrations → Team Keys, role Developer; download the .p8 and
#     note the Issuer ID shown above the list; or
#   - with no .p8 given, your Apple ID and an app-specific password made at
#     account.apple.com → Sign-In and Security → App-Specific Passwords.
#
# The .provisionprofile lets the released Mac app sync with iCloud: at
# developer.apple.com → Profiles, a Developer ID profile (Mac Catalyst) for the
# app's id, which has the iCloud capability, and that certificate.
#
# Needs the GitHub CLI, signed in (`gh auth login`), in a clone of the repository.

set -euo pipefail

P12="${1:-}"
P8="${2:-}"
PROFILE="${3:-}"
# The profile may be given without a .p8.
if [[ "$P8" == *.provisionprofile ]]; then PROFILE="$P8"; P8=""; fi
if [[ -z "$P12" || ! -f "$P12" || ( -n "$P8" && ! -f "$P8" ) || ( -n "$PROFILE" && ! -f "$PROFILE" ) ]]; then
    sed -n '3,23p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
fi

set_secret() { printf '%s' "$2" | gh secret set "$1" >/dev/null && printf '  set %s\n' "$1"; }

read -r -s -p "Password of $(basename "$P12"): " p12_password; printf '\n'
subject="$(openssl pkcs12 -in "$P12" -nokeys -passin "pass:$p12_password" 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null || true)"
if [[ "$subject" != *"Developer ID Application"* ]]; then
    printf 'That password does not open the file, or it holds no Developer ID Application certificate.\n' >&2
    exit 1
fi

if [[ -n "$P8" ]]; then
    key_id="$(basename "$P8" .p8)"; key_id="${key_id#AuthKey_}"
    read -r -p "Key ID [$key_id]: " answer; key_id="${answer:-$key_id}"
    read -r -p "Issuer ID: " issuer_id
    [[ -n "$issuer_id" ]] || { printf 'An Issuer ID is needed.\n' >&2; exit 1; }
else
    read -r -p "Apple ID: " apple_id
    read -r -s -p "App-specific password: " apple_password; printf '\n'
    [[ -n "$apple_id" && -n "$apple_password" ]] || { printf 'Both are needed.\n' >&2; exit 1; }
fi

printf 'Setting secrets on %s\n' "$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
base64 < "$P12" | tr -d '\n' | gh secret set DEVELOPER_ID_P12 >/dev/null && printf '  set DEVELOPER_ID_P12\n'
set_secret DEVELOPER_ID_P12_PASSWORD "$p12_password"
if [[ -n "$P8" ]]; then
    gh secret set NOTARY_KEY < "$P8" >/dev/null && printf '  set NOTARY_KEY\n'
    set_secret NOTARY_KEY_ID "$key_id"
    set_secret NOTARY_ISSUER_ID "$issuer_id"
    for name in NOTARY_APPLE_ID NOTARY_PASSWORD; do gh secret delete "$name" >/dev/null 2>&1 || true; done
else
    set_secret NOTARY_APPLE_ID "$apple_id"
    set_secret NOTARY_PASSWORD "$apple_password"
    for name in NOTARY_KEY NOTARY_KEY_ID NOTARY_ISSUER_ID; do gh secret delete "$name" >/dev/null 2>&1 || true; done
fi
if [[ -n "$PROFILE" ]]; then
    base64 < "$PROFILE" | tr -d '\n' | gh secret set MAC_PROVISIONING_PROFILE >/dev/null && printf '  set MAC_PROVISIONING_PROFILE\n'
fi
printf 'Done. Publish a release with: git tag v<version> && git push origin v<version>\n'
