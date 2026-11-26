#!/bin/bash

# Build Rayon and install it on this Mac and on every iPhone and iPad that is
# paired with it and reachable (over USB or the local network).
#
# Usage:
#   bash Workflow/Scripts/install.sh            # Mac and devices
#   bash Workflow/Scripts/install.sh mac        # /Applications only
#   bash Workflow/Scripts/install.sh ios        # iPhone and iPad only
#
# The Mac app is installed by install-macos.sh. A running copy is asked to
# quit first, as ⌘Q would; if it is still running after a minute (a question
# left unanswered, say), nothing is replaced.
#
# The iOS app is built unsigned, then signed with the Apple Development
# certificate and a provisioning profile: the one made for its bundle id when
# there is one (that is what lets it sync with iCloud), else the team's
# wildcard profile, which needs no registration. A device this Mac cannot reach (no cable, and not
# found on the local network) is skipped and named at the end.
#
# Environment overrides:
#   DEVELOPMENT_TEAM      Team for the iOS signature (default: the certificate's)
#   CODE_SIGN_IDENTITY    Certificate (default: the first Apple Development one)
#   PROVISIONING_PROFILE  Path to a .mobileprovision (default: see above)
#   DERIVED_DATA_PATH     Build products directory (default: .build/DerivedData)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/DerivedData}"
BUNDLE_ID="me.mizorewww.rayon"
TARGET="${1:-all}"

case "$TARGET" in
    all|mac|ios) ;;
    *) printf 'Usage: bash %s [all|mac|ios]\n' "$0" >&2; exit 2 ;;
esac

step() { printf '\n==> %s\n' "$*"; }
failed=()

# MARK: - Mac

install_mac() {
    step "Mac: building and installing to /Applications"
    if bash "$ROOT_DIR/Workflow/Scripts/install-macos.sh"; then
        open "/Applications/Rayon.app"
    else
        failed+=("Mac (build or install failed)")
    fi
}

# MARK: - iPhone and iPad

signing_identity() {
    if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
        printf '%s' "$CODE_SIGN_IDENTITY"
    else
        security find-identity -v -p codesigning \
            | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1
    fi
}

certificate_team() {
    security find-certificate -c "$1" -p \
        | openssl x509 -noout -subject -nameopt multiline \
        | sed -n 's/^ *organizationalUnitName *= *//p' | head -1
}

# Paired iPhones and iPads, as "identifier<TAB>name<TAB>transport"; the
# transport is "none" when the Mac has no route to the device.
paired_devices() {
    local json
    json="$(mktemp)"
    xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || true
    /usr/bin/python3 - "$json" <<'EOF'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for d in devices:
    hardware = d.get("hardwareProperties", {})
    if hardware.get("reality") != "physical" or hardware.get("platform") != "iOS":
        continue
    if d.get("connectionProperties", {}).get("pairingState") != "paired":
        continue
    connection = d.get("connectionProperties", {})
    transport = connection.get("transportType") or "none"
    if connection.get("tunnelState") == "unavailable":
        transport = "none"
    print(f'{d["identifier"]}\t{d["deviceProperties"]["name"]}\t{transport}')
EOF
    rm -f "$json"
}

install_ios() {
    step "iOS: building for iPhone and iPad"
    local identity team profile
    identity="$(signing_identity)"
    if [[ -z "$identity" ]]; then
        printf 'No Apple Development certificate in the keychain.\n' >&2
        failed+=("iOS (no signing certificate)")
        return
    fi
    team="${DEVELOPMENT_TEAM:-$(certificate_team "$identity")}"
    profile="${PROVISIONING_PROFILE:-$(bash "$ROOT_DIR/Workflow/Scripts/provisioning-profile.sh" \
        mobileprovision "$team" "$BUNDLE_ID" "$identity" wildcard)}"
    if [[ -z "$profile" ]]; then
        printf 'No provisioning profile for %s or wildcard one for team %s. Open Xcode once with that team signed in.\n' "$BUNDLE_ID" "$team" >&2
        failed+=("iOS (no provisioning profile)")
        return
    fi

    local ios_data="$DERIVED_DATA_PATH/iOS"
    if ! xcodebuild \
        -workspace "$ROOT_DIR/App.xcworkspace" \
        -scheme mRayon \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -derivedDataPath "$ios_data" \
        CODE_SIGNING_ALLOWED=NO \
        build > "$ios_data.log" 2>&1; then
        grep -E 'error:' "$ios_data.log" | sort -u | head -20 >&2
        printf 'iOS build failed; the full log is %s\n' "$ios_data.log" >&2
        failed+=("iOS (build failed)")
        return
    fi

    step "iOS: signing ($identity, team $team)"
    local app="$ios_data/Signed/Rayon.app"
    rm -rf "$ios_data/Signed"
    mkdir -p "$ios_data/Signed"
    ditto "$ios_data/Build/Products/Release-iphoneos/mRayon.app" "$app"
    cp "$profile" "$app/embedded.mobileprovision"
    local entitlements="$ios_data/Signed/entitlements.plist"
    cat > "$entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>application-identifier</key>
    <string>$team.$BUNDLE_ID</string>
    <key>com.apple.developer.team-identifier</key>
    <string>$team</string>
    <key>get-task-allow</key>
    <true/>
    <key>keychain-access-groups</key>
    <array>
        <string>$team.$BUNDLE_ID</string>
    </array>
</dict>
</plist>
EOF
    # A profile that grants the iCloud container (not the wildcard one: that
    # takes an app id registered with the iCloud capability) lets the app
    # sync; the app looks for the same thing in the profile.
    local grants profile_plist aps
    grants="$(security cms -D -i "$profile" 2>/dev/null || true)"
    if [[ "$grants" == *iCloud.me.mizorewww.rayon* ]]; then
        /usr/libexec/PlistBuddy \
            -c 'Add :com.apple.developer.icloud-container-identifiers array' \
            -c 'Add :com.apple.developer.icloud-container-identifiers:0 string iCloud.me.mizorewww.rayon' \
            -c 'Add :com.apple.developer.icloud-services array' \
            -c 'Add :com.apple.developer.icloud-services:0 string CloudKit' "$entitlements"
        profile_plist="$ios_data/Signed/profile.plist"
        printf '%s' "$grants" > "$profile_plist"
        aps="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:aps-environment' "$profile_plist" 2>/dev/null || true)"
        rm -f "$profile_plist"
        if [[ -n "$aps" ]]; then
            /usr/libexec/PlistBuddy -c "Add :aps-environment string $aps" "$entitlements"
        fi
    fi
    # Nested code first, then the app with its entitlements.
    find "$app" -depth \( -name '*.framework' -o -name '*.dylib' -o -name '*.appex' \) -print0 \
        | while IFS= read -r -d '' nested; do
            /usr/bin/codesign --force --sign "$identity" --timestamp=none "$nested"
        done
    /usr/bin/codesign --force --sign "$identity" --timestamp=none --entitlements "$entitlements" "$app"
    /usr/bin/codesign --verify --deep --strict "$app"

    step "iOS: installing on paired devices"
    local devices
    devices="$(paired_devices)"
    if [[ -z "$devices" ]]; then
        printf 'No paired iPhone or iPad.\n'
        return
    fi
    while IFS=$'\t' read -r identifier name transport; do
        printf '%s: ' "$name"
        if [[ "$transport" == none ]]; then
            printf 'not reachable\n'
            failed+=("$name (this Mac has no connection to it: plug it in, or put it on this Wi-Fi, then run '$0 ios')")
            continue
        fi
        local output
        if output="$(xcrun devicectl device install app --device "$identifier" "$app" 2>&1)"; then
            printf 'installed\n'
        else
            printf 'not installed\n'
            printf '%s\n' "$output" | grep -E 'ERROR|error' | head -3 | sed 's/^/    /' >&2
            failed+=("$name (reachable over $transport, but the install failed; see the error above)")
        fi
    done <<<"$devices"
}

[[ "$TARGET" == all || "$TARGET" == mac ]] && install_mac
[[ "$TARGET" == all || "$TARGET" == ios ]] && install_ios

if (( ${#failed[@]} )); then
    step "Not installed"
    printf '  - %s\n' "${failed[@]}"
    exit 1
fi
step "Done"
