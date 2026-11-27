#!/bin/bash

# Build the Mac app (native macOS, universal arm64/x86_64).
#
# Signed with the first Apple Development certificate in the keychain, so the
# signature, and the keychain's trust in it, survive rebuilds; ad hoc when
# there is none. Override with CODE_SIGN_IDENTITY / DEVELOPMENT_TEAM.
#
# With a provisioning profile made for the app's bundle id and that
# certificate, the app is also signed for CloudKit (the iCloud container
# shared with the iOS app) and with its application identifier, which the
# data protection keychain asks for; the system grants both only with one.
# It is looked for by provisioning-profile.sh; MAC_PROVISIONING_PROFILE names
# one outright.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The iCloud container, the same for every build and platform.
ICLOUD_CONTAINER="iCloud.me.mizorewww.rayon"
CONFIGURATION="${1:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/DerivedData}"

case "$CONFIGURATION" in
    Debug|Release) ;;
    *) printf 'Usage: bash %s [Debug|Release]\n' "$0" >&2; exit 2 ;;
esac

if [[ -z "${CODE_SIGN_IDENTITY:-}" ]]; then
    CODE_SIGN_IDENTITY="$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
fi
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
if [[ "$CODE_SIGN_IDENTITY" != "-" && -z "${DEVELOPMENT_TEAM:-}" ]]; then
    DEVELOPMENT_TEAM="$(security find-certificate -c "$CODE_SIGN_IDENTITY" -p \
        | openssl x509 -noout -subject -nameopt multiline \
        | sed -n 's/^ *organizationalUnitName *= *//p' | head -1)"
fi
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"

# The app's entitlements without those only a provisioning profile grants:
# signed with them and no profile, the app would not launch. sign_for_icloud
# adds them back when there is a profile.
ENTITLEMENTS="$DERIVED_DATA_PATH/Entitlements-macOS-unprovisioned.entitlements"
mkdir -p "$DERIVED_DATA_PATH"
cp "$ROOT_DIR/Application/Rayon/Resources/Entitlements/Entitlements-macOS.entitlements" "$ENTITLEMENTS"
for key in com.apple.developer.icloud-container-identifiers com.apple.developer.icloud-services \
    com.apple.developer.aps-environment keychain-access-groups; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$ENTITLEMENTS" 2>/dev/null || true
done

# The code editor's CodeEditSourceEditor runs a SwiftLint build plug-in, which
# xcodebuild would otherwise refuse to run until it is trusted in Xcode.
xcodebuild \
    -workspace "$ROOT_DIR/App.xcworkspace" \
    -scheme Rayon \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -skipPackagePluginValidation \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    COMPILER_INDEX_STORE_ENABLE=NO \
    LS_REGISTER_PRODUCT=NO \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    PROVISIONING_PROFILE_SPECIFIER= \
    build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Rayon.app"

# The profile goes into the app, and what it grants into the signature: the
# app asks its own signature whether it may sync.
sign_for_icloud() {
    [[ "$CODE_SIGN_IDENTITY" != "-" && -n "$DEVELOPMENT_TEAM" ]] || return 0
    local bundle_id profile grants entitlements key signature options=()
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
    profile="${MAC_PROVISIONING_PROFILE:-$(bash "$ROOT_DIR/Workflow/Scripts/provisioning-profile.sh" \
        provisionprofile "$DEVELOPMENT_TEAM" "$bundle_id" "$CODE_SIGN_IDENTITY")}"
    [[ -n "$profile" ]] || return 0
    # Read whole before it is searched: a search that stops at the first match
    # would fail the pipe.
    grants="$(security cms -D -i "$profile" 2>/dev/null || true)"
    [[ "$grants" == *"$ICLOUD_CONTAINER"* ]] || return 0

    entitlements="$(mktemp)"
    /usr/bin/codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null > "$entitlements"
    for key in com.apple.application-identifier com.apple.developer.team-identifier \
        com.apple.developer.icloud-container-identifiers com.apple.developer.icloud-services \
        com.apple.developer.aps-environment keychain-access-groups \
        com.apple.developer.icloud-container-environment \
        com.apple.developer.ubiquity-kvstore-identifier; do
        /usr/libexec/PlistBuddy -c "Delete :$key" "$entitlements" 2>/dev/null || true
    done
    /usr/libexec/PlistBuddy \
        -c "Add :com.apple.application-identifier string $DEVELOPMENT_TEAM.$bundle_id" \
        -c "Add :com.apple.developer.team-identifier string $DEVELOPMENT_TEAM" \
        -c 'Add :com.apple.developer.icloud-container-identifiers array' \
        -c "Add :com.apple.developer.icloud-container-identifiers:0 string $ICLOUD_CONTAINER" \
        -c 'Add :com.apple.developer.icloud-services array' \
        -c 'Add :com.apple.developer.icloud-services:0 string CloudKit' \
        -c 'Add :keychain-access-groups array' \
        -c "Add :keychain-access-groups:0 string $DEVELOPMENT_TEAM.$bundle_id" "$entitlements"
    # CloudKit tells the app of changes made elsewhere with a push; the
    # profile says to which environment.
    local profile_plist aps
    profile_plist="$(mktemp)"
    printf '%s' "$grants" > "$profile_plist"
    aps="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.aps-environment' "$profile_plist" 2>/dev/null || true)"
    rm -f "$profile_plist"
    if [[ -n "$aps" ]]; then
        /usr/libexec/PlistBuddy -c "Add :com.apple.developer.aps-environment string $aps" "$entitlements"
    fi
    # A Developer ID build has to name CloudKit's Production environment
    # itself; Xcode does that only for builds it exports.
    if [[ "$aps" == production ]]; then
        /usr/libexec/PlistBuddy -c 'Add :com.apple.developer.icloud-container-environment string Production' "$entitlements"
    fi

    cp "$profile" "$APP_PATH/Contents/embedded.provisionprofile"
    signature="$(/usr/bin/codesign -d --verbose=2 "$APP_PATH" 2>&1 || true)"
    [[ "$signature" == *"(runtime)"* ]] && options=(--options runtime)
    /usr/bin/codesign --force --sign "$CODE_SIGN_IDENTITY" ${options[@]+"${options[@]}"} --timestamp=none \
        --entitlements "$entitlements" "$APP_PATH"
    rm -f "$entitlements"
    printf 'Signed for iCloud with %s\n' "$(basename "$profile")"
}
sign_for_icloud

/usr/bin/codesign --verify --deep --strict --all-architectures --verbose=2 "$APP_PATH"
printf '\nSigned (%s): %s\n' "$CODE_SIGN_IDENTITY" "$APP_PATH"
