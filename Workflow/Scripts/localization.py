#!/usr/bin/python3
"""Keep the String Catalogs in step with the code and with each other.

  check  Fail on a key the code uses that its catalog lacks, a stale key, a
         language without a translation, or a translation whose format
         specifiers differ from the English ones.
  sync   Add the keys the code uses to the catalogs and drop the stale ones.

What the code uses comes from the .stringsdata files the compiler writes
during a build (SWIFT_EMIT_LOC_STRINGS), merged with Xcode's own
`xcstringstool sync`, as the IDE does on every build. The keys of a file that
builds for one platform only are seen only once that platform is built: with
just one built, nothing is called stale. Without a build, `check` reviews the
translations alone.

Like FlowDown's Resources/DevKit/scripts/check_translations.py, from which
this is adapted.
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LANGUAGES = ["en", "zh-Hans", "zh-Hant"]
SOURCE_LANGUAGE = "en"
# printf-style specifiers as Foundation formats them; %% is a literal percent.
SPECIFIER = re.compile(r"%(?:(\d+)\$)?[-+ #0']*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOfFeEgGcCsSpaA%])")


def catalogs():
    paths = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "*.xcstrings"], cwd=ROOT, check=True, capture_output=True, text=True
    ).stdout.split()
    return [os.path.join(ROOT, path) for path in paths]


def owner(catalog):
    """The directory whose sources the catalog localizes: the folder above Resources."""
    return os.path.dirname(os.path.dirname(catalog)) + os.sep


def stringsdata(derived_data, configuration):
    """The compiler's .stringsdata per catalog owner, and the platforms built."""
    intermediates = os.path.join(derived_data, "Build", "Intermediates.noindex")
    pattern = os.path.join(intermediates, "*", configuration + "*", "*.build", "Objects-normal", "*", "*.stringsdata")
    found, platforms = {}, set()
    for path in glob.glob(pattern):
        try:
            with open(path, encoding="utf-8") as file:
                source = json.load(file).get("source", "")
        except (OSError, ValueError):
            continue
        # Files that are gone, or not ours (dependencies, generated accessors), say nothing.
        ours = source.startswith((os.path.join(ROOT, "Application") + os.sep, os.path.join(ROOT, "Foundation") + os.sep))
        if not ours or not os.path.exists(source):
            continue
        found.setdefault(source, []).append(path)
        # Intermediates.noindex/<project>.build/<configuration>[-<sdk>]/...
        products = os.path.relpath(path, intermediates).split(os.sep)[1]
        platforms.add("ios" if products.startswith(configuration + "-iphone") else "macos")
    return found, platforms


def load(path):
    with open(path, encoding="utf-8") as file:
        return json.load(file)


def sync(catalog, sources, mark_stale, root=None):
    """Runs xcstringstool sync on the catalog with the stringsdata of its sources."""
    root = root or owner(catalog)
    files = [f for source, paths in sources.items() if source.startswith(root) for f in paths]
    if not files:
        return False
    command = ["xcrun", "xcstringstool", "sync", catalog, "--stringsdata", *files]
    if not mark_stale:
        command.append("--skip-marking-strings-stale")
    subprocess.run(command, check=True)
    return True


def units(entry, language):
    """Every string unit of a language: the plain one or each variation's."""
    localization = entry.get("localizations", {}).get(language)
    if localization is None:
        return None
    found = []

    def walk(node):
        if "stringUnit" in node:
            found.append(node["stringUnit"])
        for cases in node.get("variations", {}).values():
            for case in cases.values():
                walk(case)

    walk(localization)
    return found


def specifiers(text):
    """The format arguments in order of position: their type, without the flags."""
    explicit, implicit = {}, []
    for match in SPECIFIER.finditer(text):
        position, length, conversion = match.groups()
        if conversion == "%":
            continue
        kind = (length or "") + conversion
        if position:
            explicit[int(position)] = kind
        else:
            implicit.append(kind)
    if explicit:
        return [explicit[key] for key in sorted(explicit)]
    return implicit


def review(key, entry):
    """The problems of one catalog entry, as sentences."""
    if entry.get("shouldTranslate") is False:
        return []
    problems = []
    # The key is what the code formats with; an English value only rewords it.
    expected = specifiers(key)
    for language in LANGUAGES:
        found = units(entry, language)
        if found is None:
            if language != SOURCE_LANGUAGE:
                problems.append(f"{language}: no translation")
            continue
        for unit in found:
            value = unit.get("value", "")
            # Xcode writes the English of a key it rewrites positionally as "new".
            reviewed = language == SOURCE_LANGUAGE or unit.get("state") == "translated"
            if not reviewed or not value.strip():
                problems.append(f"{language}: not translated (state {unit.get('state')})")
                continue
            got = specifiers(value)
            # A plural case may leave the count out ("one core"), never add or retype one.
            plural = len(found) > 1
            if got != expected and not (plural and set(got) <= set(expected)):
                problems.append(f"{language}: format {got} differs from {expected} in {value!r}")
    return problems


def check(arguments):
    sources, platforms = stringsdata(arguments.derived_data, arguments.configuration)
    complete = platforms >= {"macos", "ios"}
    if not sources:
        print("No build found in DerivedData: checking the translations only.")
    elif not complete:
        print(f"Only {', '.join(sorted(platforms))} is built: stale keys are not looked for.")
    failures = 0
    for catalog in catalogs():
        name = os.path.relpath(catalog, ROOT)
        original = load(catalog)["strings"]
        current = original
        if os.path.basename(catalog) == "Localizable.xcstrings" and sources:
            with tempfile.TemporaryDirectory() as directory:
                copy = os.path.join(directory, "Localizable.xcstrings")
                shutil.copy(catalog, copy)
                if sync(copy, sources, mark_stale=complete, root=owner(catalog)):
                    current = load(copy)["strings"]
        problems = []
        for key in sorted(set(current) - set(original)):
            problems.append(f"{key!r}: used in the code but missing from the catalog")
        for key, entry in sorted(current.items()):
            if entry.get("extractionState") == "stale":
                problems.append(f"{key!r}: stale, no longer used in the code")
            elif key in original:
                problems.extend(f"{key!r}: {problem}" for problem in review(key, original[key]))
        translatable = [e for e in original.values() if e.get("shouldTranslate") is not False]
        print(f"{name}: {len(translatable)} strings, {len(problems)} problems")
        for problem in problems:
            print(f"  {problem}")
        failures += len(problems)
    if failures:
        print("Run `make sync-localization` after building both platforms to add and drop keys,"
              " then translate what is missing.")
    return 1 if failures else 0


def run_sync(arguments):
    sources, platforms = stringsdata(arguments.derived_data, arguments.configuration)
    if not platforms >= {"macos", "ios"}:
        print("Build both platforms first (make build): a key one of them alone uses would be dropped.")
        return 1
    for catalog in catalogs():
        if os.path.basename(catalog) != "Localizable.xcstrings" or not sync(catalog, sources, mark_stale=True):
            continue
        data = load(catalog)
        stale = [key for key, entry in data["strings"].items() if entry.get("extractionState") == "stale"]
        for key in stale:
            del data["strings"][key]
        if stale:
            with open(catalog, "w", encoding="utf-8") as file:
                json.dump(data, file, ensure_ascii=False, indent=2)
            # Written back in Xcode's own layout.
            sync(catalog, sources, mark_stale=False)
        print(f"{os.path.relpath(catalog, ROOT)}: {len(data['strings'])} strings, {len(stale)} stale dropped")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("command", choices=["check", "sync"])
    parser.add_argument("--derived-data", default=os.environ.get("DERIVED_DATA_PATH", os.path.join(ROOT, ".build", "DerivedData")))
    parser.add_argument("--configuration", default=os.environ.get("CONFIGURATION", "Debug"))
    arguments = parser.parse_args()
    return check(arguments) if arguments.command == "check" else run_sync(arguments)


if __name__ == "__main__":
    sys.exit(main())
