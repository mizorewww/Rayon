#!/usr/bin/python3
"""Keep Resources/Libraries.json, the About pages' list of libraries, in step
with Resources/LICENSE, and every pinned dependency in step with both.

  check  Fail when Libraries.json differs from what LICENSE gives, or when a
         dependency pinned in a Package.resolved has no entry.
  sync   Write Libraries.json from LICENSE.

LICENSE stays the one hand-kept source: it holds notices no Package.resolved
knows of (Ghostty's engine, the grammars inside Runestone.xcframework) and
the apps ship it whole. Versions come from the pins where there is one.
Each notice there starts after a `---` or `====`
divider with a heading, `Name 1.2.3 (remark)`, then its repository URLs.
"""

import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LICENSE = os.path.join(ROOT, "Resources", "LICENSE")
OUTPUT = os.path.join(ROOT, "Resources", "Libraries.json")
PLATFORMS = ["macOS", "iOS"]
DIVIDER = re.compile(r"^(---|={3,})$")
LICENSES = [
    (re.compile(r"^(The )?MIT License"), "MIT"),
    (re.compile(r"^BSD 3-Clause License"), "BSD-3-Clause"),
    (re.compile(r"^Apache License$"), "Apache-2.0"),
]


def sections(text):
    lines = text.split("\n")
    start = 0
    for index, line in enumerate(lines + ["---"]):
        if DIVIDER.match(line.strip()):
            yield "\n".join(lines[start:index]).strip("\n")
            start = index + 1


def entries(text):
    """Every notice but the footnote, in LICENSE's order."""
    result = []
    for section in sections(text):
        lines = section.split("\n")
        heading = lines[0].strip()
        if not heading or heading.startswith("*"):
            continue
        name, _, remark = heading.partition(" (")
        remark = remark.removesuffix(")")
        version = None
        words = name.split(" ")
        if len(words) > 1 and words[-1][:1].isdigit():
            name, version = " ".join(words[:-1]), words[-1]
        urls = [line.strip() for line in lines[1:] if line.startswith("https://")]
        licenses = []
        for line in lines:
            for pattern, license in LICENSES:
                if pattern.match(line.strip()) and license not in licenses:
                    licenses.append(license)
        result.append({
            "name": name,
            "version": version,
            "remark": remark or None,
            "url": urls[0] if urls else None,
            "urls": urls,
            "license": ", ".join(licenses) or None,
            "text": "\n".join(lines[1 + len(urls):]).strip("\n"),
        })
    for entry in result:
        entry["platforms"] = platforms(entry, result)
    return result


def platforms(entry, everything):
    """Where it ships: the platforms its remark names, a build tool nowhere,
    a part of another library wherever that one ships."""
    remark = entry["remark"] or ""
    if remark.startswith("build tool only"):
        return []
    named = [platform for platform in PLATFORMS if platform in remark]
    if named:
        return named
    part = re.match(r"(built into|bundled in) ([^:;]+)", remark)
    parent = next((other for other in everything if part and other["name"] == part.group(2).strip()), None)
    return platforms(parent, everything) if parent else PLATFORMS


def display(url):
    """`owner/repo` for GitHub, the host and path for anything else."""
    match = re.match(r"https://github\.com/([^/]+/[^/]+)", url)
    return match.group(1) if match else url.removeprefix("https://")


def render(text):
    # A pinned version beats the heading's, which can lag behind an update.
    versions = {url.lower(): version for _, url, version in pinned() if version[:1].isdigit() and "." in version}
    libraries = []
    for entry in entries(text):
        version = versions.get((entry["url"] or "").lower(), entry["version"])
        libraries.append({
            "name": entry["name"],
            "version": version,
            "url": entry["url"],
            "repository": display(entry["url"]) if entry["url"] else None,
            "license": entry["license"],
            "platforms": entry["platforms"],
            "text": entry["text"],
        })
    return json.dumps(libraries, ensure_ascii=False, indent=2) + "\n"


def pinned():
    paths = subprocess.run(["git", "ls-files", "*Package.resolved"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.split()
    for path in paths:
        data = json.load(open(os.path.join(ROOT, path)))
        # Version 1 files nest the pins under "object" and call the URL "repositoryURL".
        for pin in data.get("pins") or data["object"]["pins"]:
            url = (pin.get("location") or pin["repositoryURL"]).removesuffix(".git")
            version = pin["state"].get("version") or pin["state"].get("revision", "")[:10]
            yield path, url, version


def check(text):
    failed = False
    with open(OUTPUT, encoding="utf-8") as file:
        if file.read() != render(text):
            print("Resources/Libraries.json is out of date with Resources/LICENSE: run make sync-libraries")
            failed = True
    noted = {url.lower() for entry in entries(text) for url in entry["urls"]}
    for path, url, version in pinned():
        ok = url.lower() in noted
        failed |= not ok
        print(f"{'ok     ' if ok else 'MISSING'}  {url} {version}  ({path})")
    return failed


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    with open(LICENSE, encoding="utf-8") as file:
        text = file.read()
    if command == "sync":
        with open(OUTPUT, "w", encoding="utf-8") as file:
            file.write(render(text))
    elif command == "check":
        sys.exit(1 if check(text) else 0)
    else:
        sys.exit(f"usage: {sys.argv[0]} check|sync")


if __name__ == "__main__":
    main()
