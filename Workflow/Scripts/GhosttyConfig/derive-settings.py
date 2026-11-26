"""Reduces the exported Ghostty Config catalog to the data Rayon bundles.

usage: python3 derive-settings.py catalog.json ghosttytheme-names.txt OUT_DIR

Writes OUT_DIR/settings.json (every option in the upstream category order,
with its section, and widgets without web-only fields) and OUT_DIR/themes.json
(the catalog themes that GhosttyTheme does not ship; names one per line in
ghosttytheme-names.txt).
"""
import json
import sys

catalog_path, names_path, out_dir = sys.argv[1:4]
catalog = json.load(open(catalog_path))
registry = catalog["registry"]

settings = []
for category in catalog["navigation"]:
    for group in category["groups"]:
        section = category["name"] + (" · " + group["name"] if group["name"] else "")
        for setting_id in group["settings"]:
            setting = dict(registry[setting_id])
            widget = setting.get("widget")
            if widget:
                widget = dict(widget)
                if widget.get("type") == "theme":
                    # Themes come from GhosttyTheme and themes.json.
                    widget.pop("options", None)
                if "options" in widget:
                    widget["options"] = [
                        {k: v for k, v in option.items() if k not in ("icon", "group")}
                        if isinstance(option, dict) else option
                        for option in widget["options"]
                    ]
                setting["widget"] = widget
            setting["section"] = section
            settings.append(setting)
assert len(settings) == len(registry), "a setting is missing from the navigation"

with open(f"{out_dir}/settings.json", "w") as f:
    json.dump({"revision": catalog["revision"], "settings": settings}, f, ensure_ascii=False, indent=1)
    f.write("\n")

shipped = {line.strip() for line in open(names_path) if line.strip()}
themes = [
    {"name": name, **theme}
    for name, theme in sorted(catalog["themes"].items())
    if name not in shipped
]
with open(f"{out_dir}/themes.json", "w") as f:
    json.dump(themes, f, ensure_ascii=False, indent=1)
    f.write("\n")
