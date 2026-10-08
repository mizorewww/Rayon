#!/bin/bash

# Build Rayon in Release configuration and install it to /Applications.
#
# Usage:
#   bash Workflow/Scripts/install-macos.sh
#
# Environment overrides:
#   INSTALL_DIR        Target directory (default: /Applications)
#   DERIVED_DATA_PATH  Build products directory (default: ./DerivedData)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="Rayon.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/DerivedData}"

# 1. Build Release (universal arm64/x86_64, locally signed, codesign-verified).
bash "$ROOT_DIR/Workflow/Scripts/build-macos.sh" Release

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME"
DEST="$INSTALL_DIR/$APP_NAME"

if [[ ! -d "$APP_PATH" ]]; then
    printf 'error: build product not found at %s\n' "$APP_PATH" >&2
    exit 1
fi

# 2. Replace any existing installation. Prefer the Trash when possible.
if [[ -d "$DEST" ]]; then
    printf 'Replacing existing %s\n' "$DEST"
    if command -v trash >/dev/null 2>&1; then
        trash "$DEST"
    else
        rm -rf "$DEST"
    fi
fi

# 3. Install. ditto preserves bundle metadata better than cp -R.
ditto "$APP_PATH" "$DEST"

# Locally built apps carry no quarantine attribute, but clear it in case
# the derived-data path ever does (e.g. after transferring an archive).
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

printf '\nInstalled: %s\n' "$DEST"
printf 'Launch with: open %s\n' "$DEST"
