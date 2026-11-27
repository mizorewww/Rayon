import Foundation

/// How the terminal's settings are organised: categories ordered from what
/// people change most (the text and colours) to what they rarely touch
/// (Advanced). Each category holds titled groups of catalog keys. Settings
/// that take no effect inside Rayon close the list, grouped as Ghostty's
/// documentation groups them, so every option stays reachable. The app
/// places the categories in its own Settings.
enum SettingsLayout {
    struct Group: Identifiable {
        let id: String
        let title: String
        let keys: [String]
        var footer: String?

        init(_ id: String, _ title: String, keys: [String], footer: String? = nil) {
            self.id = id
            self.title = title
            self.keys = keys
            self.footer = footer
        }
    }

    struct Category: Identifiable {
        let id: String
        let title: String
        let icon: String
        let groups: [Group]
        /// Said above the category's settings.
        var note: String?

        /// Ghostty keys in this category.
        var keys: [String] {
            groups.flatMap(\.keys)
        }

        /// Shows the live terminal preview with it.
        var previews: Bool {
            id != "keyboard" && id != Self.ghosttyID
        }

        static let ghosttyID = "ghostty"
    }

    static let categories: [Category] = rayonCategories + [ghosttyCategory]

    /// Every option Rayon's terminal does not use, in Ghostty's documentation order.
    private static let ghosttyCategory: Category = {
        let shown = Set(rayonCategories.flatMap(\.keys))
        var groups: [Group] = []
        for setting in SettingCatalog.shared.settings where !shown.contains(setting.key) {
            if let index = groups.firstIndex(where: { $0.id == setting.section }) {
                groups[index] = Group(setting.section, setting.section, keys: groups[index].keys + [setting.key])
            } else {
                groups.append(Group(setting.section, setting.section, keys: [setting.key]))
            }
        }
        return Category(
            id: Category.ghosttyID, title: String(localized: "Ghostty App", bundle: .module), icon: "app.dashed", groups: groups,
            note: String(localized: "Rayon's terminal does not use these: they belong to the Ghostty app, or Rayon sets them itself. They are kept in config.ghostty, so the file also works in Ghostty.", bundle: .module)
        )
    }()

    private static let rayonCategories: [Category] = [
        Category(id: "text", title: String(localized: "Text", bundle: .module), icon: "textformat", groups: [
            Group("font", String(localized: "Font", bundle: .module), keys: ["font-family", "font-style", "font-size", "font-thicken", "font-thicken-strength"]),
            Group("styles", String(localized: "Bold and Italic", bundle: .module), keys: [
                "font-family-bold", "font-style-bold", "font-family-italic", "font-style-italic",
                "font-family-bold-italic", "font-style-bold-italic", "font-synthetic-style",
            ]),
            Group("features", String(localized: "Features and Variations", bundle: .module), keys: [
                "font-feature", "font-variation", "font-variation-bold", "font-variation-italic", "font-variation-bold-italic",
            ]),
            Group("glyphs", String(localized: "Glyphs", bundle: .module), keys: ["font-codepoint-map", "grapheme-width-method"]),
            Group("metrics", String(localized: "Cell Metrics", bundle: .module), keys: [
                "adjust-cell-width", "adjust-cell-height", "adjust-font-baseline",
                "adjust-underline-position", "adjust-underline-thickness",
                "adjust-strikethrough-position", "adjust-strikethrough-thickness",
                "adjust-overline-position", "adjust-overline-thickness", "adjust-box-thickness",
            ]),
        ]),
        Category(id: "colors", title: String(localized: "Colors", bundle: .module), icon: "paintpalette", groups: [
            Group("theme", String(localized: "Theme", bundle: .module), keys: ["theme"]),
            Group("base", String(localized: "Text and Background", bundle: .module), keys: ["foreground", "background", "bold-color", "minimum-contrast"]),
            Group("selection", String(localized: "Selection", bundle: .module), keys: ["selection-foreground", "selection-background"]),
            Group("palette", String(localized: "Palette", bundle: .module), keys: ["palette"]),
        ]),
        Category(id: "cursor", title: String(localized: "Cursor", bundle: .module), icon: "character.cursor.ibeam", groups: [
            Group("shape", String(localized: "Shape", bundle: .module), keys: ["cursor-style", "cursor-style-blink", "adjust-cursor-thickness", "adjust-cursor-height"]),
            Group("color", String(localized: "Color", bundle: .module), keys: ["cursor-color", "cursor-text", "cursor-opacity"]),
        ]),
        Category(id: "window", title: String(localized: "Window", bundle: .module), icon: "macwindow", groups: [
            Group("transparency", String(localized: "Transparency", bundle: .module), keys: ["background-opacity", "background-opacity-cells"]),
            Group("padding", String(localized: "Padding", bundle: .module), keys: ["window-padding-x", "window-padding-y", "window-padding-balance", "window-padding-color"]),
        ]),
        Category(id: "input", title: String(localized: "Mouse & Clipboard", bundle: .module), icon: "cursorarrow.click", groups: [
            // Copy on Select is the app's own row: a touch selection never
            // passes through Ghostty's `copy-on-select`.
            Group("copy", String(localized: "Copy and Paste", bundle: .module), keys: [
                "clipboard-trim-trailing-spaces", "selection-clear-on-copy",
                "selection-clear-on-typing", "clipboard-paste-protection", "clipboard-paste-bracketed-safe",
            ]),
            Group("mouse", String(localized: "Mouse", bundle: .module), keys: ["mouse-scroll-multiplier", "mouse-hide-while-typing", "mouse-shift-capture", "cursor-click-to-move", "link-url"]),
        ]),
        Category(id: "keyboard", title: String(localized: "Keyboard", bundle: .module), icon: "keyboard", groups: [
            Group("keybinds", String(localized: "Shortcuts", bundle: .module), keys: ["keybind"]),
        ]),
        Category(id: "advanced", title: String(localized: "Advanced", bundle: .module), icon: "slider.horizontal.3", groups: [
            Group("memory", String(localized: "Memory", bundle: .module), keys: ["scrollback-limit", "image-storage-limit"]),
            Group("compatibility", String(localized: "Compatibility", bundle: .module), keys: ["title", "enquiry-response", "vt-kam-allowed"]),
        ]),
    ]

    static let categoryOfKey: [String: Category] = {
        var result: [String: Category] = [:]
        for category in categories {
            for key in category.keys where result[key] == nil {
                result[key] = category
            }
        }
        return result
    }()

    static func category(_ id: String) -> Category? {
        categories.first { $0.id == id }
    }

    // MARK: Wording

    /// Rayon's wording where the catalog's is written for standalone Ghostty, or
    /// no longer matches the control (sizes edited in MB, fonts picked from a list).
    static let wording: [String: (title: String, summary: String?)] = [
        "font-family": (String(localized: "Font", bundle: .module), String(localized: "The typeface for terminal text, then fallbacks for characters it lacks.", bundle: .module)),
        "font-style": (String(localized: "Style", bundle: .module), String(localized: "Which of the font's styles regular text uses.", bundle: .module)),
        "font-size": (String(localized: "Size", bundle: .module), String(localized: "Text size in points. ⌘+ and ⌘− change it for one session.", bundle: .module)),
        "font-thicken": (String(localized: "Thicken strokes", bundle: .module), String(localized: "Draw text with a heavier stroke, like Terminal on macOS.", bundle: .module)),
        "font-thicken-strength": (String(localized: "Thickening amount", bundle: .module), String(localized: "How much heavier strokes are drawn while thickening is on.", bundle: .module)),
        "font-family-bold": (String(localized: "Bold font", bundle: .module), nil),
        "font-style-bold": (String(localized: "Bold style", bundle: .module), nil),
        "font-family-italic": (String(localized: "Italic font", bundle: .module), nil),
        "font-style-italic": (String(localized: "Italic style", bundle: .module), nil),
        "font-family-bold-italic": (String(localized: "Bold italic font", bundle: .module), nil),
        "font-style-bold-italic": (String(localized: "Bold italic style", bundle: .module), nil),
        "font-feature": (String(localized: "OpenType features", bundle: .module), String(localized: "Turn ligatures and stylistic alternates on or off.", bundle: .module)),
        "font-variation": (String(localized: "Variation axes", bundle: .module), String(localized: "Weight, width or slant of a variable font.", bundle: .module)),
        "font-variation-bold": (String(localized: "Bold variation axes", bundle: .module), nil),
        "font-variation-italic": (String(localized: "Italic variation axes", bundle: .module), nil),
        "font-variation-bold-italic": (String(localized: "Bold italic variation axes", bundle: .module), nil),
        "font-codepoint-map": (String(localized: "Font for character ranges", bundle: .module), String(localized: "Draw specific Unicode ranges, such as icons, with another font.", bundle: .module)),
        "background-opacity": (String(localized: "Background opacity", bundle: .module), String(localized: "Below 1, the window behind shows through the terminal background.", bundle: .module)),
        "background-opacity-cells": (String(localized: "Apply opacity to colored cells", bundle: .module), String(localized: "Also make cells with their own background color translucent.", bundle: .module)),
        "window-padding-x": (String(localized: "Horizontal padding", bundle: .module), String(localized: "Space between the text and the left and right edges, in points.", bundle: .module)),
        "window-padding-y": (String(localized: "Vertical padding", bundle: .module), String(localized: "Space between the text and the top and bottom edges, in points.", bundle: .module)),
        "window-padding-balance": (String(localized: "Balance padding", bundle: .module), String(localized: "Spread leftover space evenly around the text.", bundle: .module)),
        "scrollback-limit": (String(localized: "Scrollback", bundle: .module), String(localized: "Memory kept for lines that have scrolled off screen.", bundle: .module)),
        "image-storage-limit": (String(localized: "Images", bundle: .module), String(localized: "Memory kept for images shown in the terminal.", bundle: .module)),
        "title": (String(localized: "Fixed session title", bundle: .module), String(localized: "Use this instead of the title the remote shell sets.", bundle: .module)),
        "mouse-scroll-multiplier": (String(localized: "Scroll speed", bundle: .module), String(localized: "Multiplies trackpad (precise) and mouse wheel (line) scrolling.", bundle: .module)),
        "cursor-click-to-move": (String(localized: "Option-click moves the cursor", bundle: .module), String(localized: "Option-click at a prompt to move the cursor there.", bundle: .module)),
        "link-url": (String(localized: "Detect links", bundle: .module), String(localized: "⌘-click URLs in terminal output to open them.", bundle: .module)),
        "cursor-style": (String(localized: "Style", bundle: .module), nil),
        "cursor-style-blink": (String(localized: "Blinking", bundle: .module), String(localized: "Whether the cursor blinks; programs can still ask for either.", bundle: .module)),
        "adjust-cursor-thickness": (String(localized: "Bar thickness", bundle: .module), String(localized: "Width of the bar and hollow-block cursor, in points or percent.", bundle: .module)),
        "adjust-cursor-height": (String(localized: "Height", bundle: .module), String(localized: "Height of the cursor, in points or percent.", bundle: .module)),
        "cursor-color": (String(localized: "Fill", bundle: .module), String(localized: "Color of the cursor itself.", bundle: .module)),
        "cursor-text": (String(localized: "Text under the cursor", bundle: .module), nil),
        "cursor-opacity": (String(localized: "Opacity", bundle: .module), nil),
    ]

    static func title(_ setting: Setting) -> String {
        wording[setting.key]?.title ?? setting.name
    }

    static func summary(_ setting: Setting) -> String {
        wording[setting.key].flatMap(\.summary) ?? setting.summary
    }

    /// Human names for option values the catalog leaves raw.
    static let optionNames: [String: [String: String]] = [
        "cursor-style": ["block": String(localized: "Block", bundle: .module),
        "bar": String(localized: "Bar", bundle: .module),
        "underline": String(localized: "Underline", bundle: .module),
        "block_hollow": String(localized: "Hollow", bundle: .module)],
        "cursor-style-blink": ["true": String(localized: "Blink", bundle: .module),
        "false": String(localized: "Steady", bundle: .module),
        "": String(localized: "Auto", bundle: .module)],
        "mouse-shift-capture": ["false": String(localized: "Off (programs can opt in)", bundle: .module),
        "true": String(localized: "On (programs can opt out)", bundle: .module),
        "always": String(localized: "Always", bundle: .module),
        "never": String(localized: "Never", bundle: .module)],
        "window-padding-color": ["background": String(localized: "Background color", bundle: .module),
        "extend": String(localized: "Extend edge cells", bundle: .module),
        "extend-always": String(localized: "Always extend edge cells", bundle: .module)],
    ]

    static func optionName(_ key: String, value: String, fallback: String) -> String {
        optionNames[key]?[value] ?? fallback
    }
}
