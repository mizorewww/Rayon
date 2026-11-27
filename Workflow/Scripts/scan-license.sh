#!/bin/bash

# List every dependency pinned in a Package.resolved, and fail when one has no
# notice in Resources/LICENSE or Resources/Libraries.json is out of date with it.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
/usr/bin/python3 "$ROOT_DIR/Workflow/Scripts/libraries.py" check
