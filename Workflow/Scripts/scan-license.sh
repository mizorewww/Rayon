#!/bin/bash

# List every dependency pinned in a Package.resolved, and fail when one is not
# named (by its repository URL) in Resources/LICENSE, the notices the apps ship.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

git ls-files '*Package.resolved' | /usr/bin/python3 -c '
import json, sys
notices = open("Resources/LICENSE").read().lower()
missing = 0
for path in sys.stdin.read().split():
    data = json.load(open(path))
    # Version 1 files nest the pins under "object" and call the URL "repositoryURL".
    for pin in data.get("pins") or data["object"]["pins"]:
        url = (pin.get("location") or pin["repositoryURL"]).removesuffix(".git")
        version = pin["state"].get("version") or pin["state"].get("revision", "")[:10]
        noted = url.lower() in notices
        missing += not noted
        status = "ok     " if noted else "MISSING"
        print(f"{status}  {url} {version}  ({path})")
sys.exit(1 if missing else 0)
'
