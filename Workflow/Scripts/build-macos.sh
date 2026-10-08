#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIGURATION="${1:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/DerivedData}"

case "$CONFIGURATION" in
    Debug|Release) ;;
    *) printf 'Usage: bash %s [Debug|Release]\n' "$0" >&2; exit 2 ;;
esac

xcodebuild \
    -workspace "$ROOT_DIR/App.xcworkspace" \
    -scheme Rayon \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

printf '\nUnsigned application: %s/Build/Products/%s/Rayon.app\n' "$DERIVED_DATA_PATH" "$CONFIGURATION"
