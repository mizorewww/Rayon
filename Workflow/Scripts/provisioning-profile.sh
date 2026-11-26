#!/bin/bash

# Print the path of the provisioning profile to sign an app with, or nothing.
#
# Usage:
#   bash Workflow/Scripts/provisioning-profile.sh <kind> <team> <bundle id> <identity> [wildcard]
#
# <kind> is mobileprovision (iOS) or provisionprofile (Mac). The profile is the
# team's, unexpired, and holds the certificate named <identity>. One made for
# the bundle id is preferred; with "wildcard", the team's "*" profile will do
# when there is none. Among equals, the one that expires last.
#
# Profiles are looked for where Xcode keeps them, and in $DERIVED_DATA_PATH/signing.

set -euo pipefail

KIND="$1" TEAM="$2" BUNDLE_ID="$3" IDENTITY="$4" WILDCARD="${5:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/DerivedData}"

certificate="$(security find-certificate -c "$IDENTITY" -p 2>/dev/null \
    | openssl x509 -outform der 2>/dev/null | openssl dgst -sha1 -r | cut -d' ' -f1)"

for file in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*."$KIND" \
            "$HOME/Library/MobileDevice/Provisioning Profiles"/*."$KIND" \
            "$DERIVED_DATA_PATH/signing"/*."$KIND"; do
    [[ -f "$file" ]] || continue
    printf '%s\t' "$file"
    security cms -D -i "$file" 2>/dev/null | base64 | tr -d '\n'
    printf '\n'
done | /usr/bin/python3 -c '
import base64, datetime, hashlib, plistlib, sys
team, bundle_id, certificate, wildcard = sys.argv[1:5]
best = None
for line in sys.stdin:
    path, _, data = line.rstrip("\n").partition("\t")
    try:
        profile = plistlib.loads(base64.b64decode(data))
    except Exception:
        continue
    entitlements = profile.get("Entitlements", {})
    app_id = entitlements.get("application-identifier") or entitlements.get("com.apple.application-identifier")
    if app_id == team + "." + bundle_id:
        exact = 1
    elif wildcard and app_id == team + ".*":
        exact = 0
    else:
        continue
    expiry = profile.get("ExpirationDate")
    if not expiry or expiry <= datetime.datetime.utcnow():
        continue
    held = {hashlib.sha1(bytes(c)).hexdigest() for c in profile.get("DeveloperCertificates", [])}
    if certificate not in held:
        continue
    if best is None or (exact, expiry) > best[:2]:
        best = (exact, expiry, path)
print(best[2] if best else "", end="")
' "$TEAM" "$BUNDLE_ID" "$certificate" "$WILDCARD"
