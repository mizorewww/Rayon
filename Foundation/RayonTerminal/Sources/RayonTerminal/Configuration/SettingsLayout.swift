import Foundation

/// How the terminal's settings are organised: categories ordered from what
/// people change most (the text and colours) to what they rarely touch
/// (Advanced). Each category holds titled groups of catalog keys; the
/// catalog holds only options that take effect inside Rayon. The app places
/// the categories in its own Settings.
enum SettingsLayout {
    struct Group: Identifiable {
        let id: String
        let title: String
        let keys: [String]
        var footer: String?
        /// Opens as a page of its own from a row on its category's page. A
        /// grouped form lays out every row it holds, not just the visible
        /// ones, so a long category keeps its page short this way.
        var isSubpage = false

        init(_ id: String, _ title: String, keys: [String], footer: String? = nil, isSubpage: Bool = false) {
            self.id = id
            self.title = title
            self.keys = keys
            self.footer = footer
            self.isSubpage = isSubpage
        }
    }

    struct Category: Identifiable {
        let id: String
        let title: String
        let icon: String
        let groups: [Group]

        /// Ghostty keys in this category.
        var keys: [String] {
            groups.flatMap(\.keys)
        }

        /// Shows the live terminal preview with it.
        var previews: Bool {
            id != "keyboard"
        }
    }

    static let categories: [Category] = [
        Category(id: "text", title: String(localized: "Text", bundle: .module), icon: "textformat", groups: [
            Group("font", String(localized: "Font", bundle: .module), keys: ["font-family", "font-style", "font-size", "font-thicken", "font-thicken-strength"]),
            Group("styles", String(localized: "Bold and Italic", bundle: .module), keys: [
                "font-family-bold", "font-style-bold", "font-family-italic", "font-style-italic",
                "font-family-bold-italic", "font-style-bold-italic", "font-synthetic-style",
            ], isSubpage: true),
            Group("features", String(localized: "Features and Variations", bundle: .module), keys: [
                "font-feature", "font-shaping-break", "font-variation", "font-variation-bold", "font-variation-italic", "font-variation-bold-italic",
            ], isSubpage: true),
            Group("glyphs", String(localized: "Glyphs", bundle: .module), keys: ["font-codepoint-map", "grapheme-width-method"], isSubpage: true),
            Group("metrics", String(localized: "Cell Metrics", bundle: .module), keys: [
                "adjust-cell-width", "adjust-cell-height", "adjust-font-baseline",
                "adjust-underline-position", "adjust-underline-thickness",
                "adjust-strikethrough-position", "adjust-strikethrough-thickness",
                "adjust-overline-position", "adjust-overline-thickness", "adjust-box-thickness", "adjust-icon-height",
            ], isSubpage: true),
        ]),
        Category(id: "colors", title: String(localized: "Colors", bundle: .module), icon: "paintpalette", groups: [
            Group("theme", String(localized: "Theme", bundle: .module), keys: ["theme"]),
            Group("base", String(localized: "Text and Background", bundle: .module), keys: ["foreground", "background", "bold-color", "faint-opacity", "minimum-contrast"]),
            Group("selection", String(localized: "Selection", bundle: .module), keys: ["selection-foreground", "selection-background"]),
            Group("palette", String(localized: "Palette", bundle: .module), keys: ["palette", "palette-generate", "palette-harmonious"], isSubpage: true),
            Group("find", String(localized: "Find", bundle: .module), keys: [
                "search-foreground", "search-background", "search-selected-foreground", "search-selected-background",
            ], isSubpage: true),
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
            Group("mouse", String(localized: "Mouse", bundle: .module), keys: [
                "mouse-scroll-multiplier", "scroll-to-bottom", "mouse-hide-while-typing", "mouse-reporting", "mouse-shift-capture",
                "cursor-click-to-move", "link-url", "right-click-action", "middle-click-action", "click-repeat-interval", "selection-word-chars",
            ], isSubpage: true),
        ]),
        Category(id: "keyboard", title: String(localized: "Keyboard", bundle: .module), icon: "keyboard", groups: keyboardGroups),
        Category(id: "advanced", title: String(localized: "Advanced", bundle: .module), icon: "slider.horizontal.3", groups: [
            Group("memory", String(localized: "Memory", bundle: .module), keys: ["scrollback-limit", "image-storage-limit"]),
            Group("rendering", String(localized: "Rendering", bundle: .module), keys: ["alpha-blending", "window-colorspace"]),
            Group("compatibility", String(localized: "Compatibility", bundle: .module), keys: [
                "title", "title-report", "osc-color-report-format", "enquiry-response", "vt-kam-allowed",
            ], isSubpage: true),
        ]),
    ]

    private static var keyboardGroups: [Group] {
        var groups = [Group("keybinds", String(localized: "Shortcuts", bundle: .module), keys: ["keybind"])]
        #if os(macOS)
            // libghostty reads the Option key setting only on macOS.
            groups.insert(Group("option", String(localized: "Option Key", bundle: .module), keys: ["macos-option-as-alt"]), at: 0)
        #endif
        return groups
    }

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
        "font-shaping-break": (String(localized: "Break ligatures at", bundle: .module), String(localized: "Where text is split so no ligature forms across it.", bundle: .module)),
        "adjust-icon-height": (String(localized: "Icon height", bundle: .module), String(localized: "Largest height of Nerd Font icons, in points or percent; Powerline symbols keep theirs.", bundle: .module)),
        "faint-opacity": (String(localized: "Faint text opacity", bundle: .module), String(localized: "How opaque dim text is, from 0 (invisible) to 1 (solid).", bundle: .module)),
        "palette-generate": (String(localized: "Generate extended colors", bundle: .module), String(localized: "Derive colors 16 to 255 from the 16 base colors; colors you set are kept.", bundle: .module)),
        "palette-harmonious": (String(localized: "Reverse generated colors", bundle: .module), String(localized: "Invert the generated colors, so programs that use them suit light and dark backgrounds.", bundle: .module)),
        "search-foreground": (String(localized: "Match text", bundle: .module), String(localized: "Text of every match while finding. Cell colors work too.", bundle: .module)),
        "search-background": (String(localized: "Match background", bundle: .module), nil),
        "search-selected-foreground": (String(localized: "Current match text", bundle: .module), nil),
        "search-selected-background": (String(localized: "Current match background", bundle: .module), nil),
        "scroll-to-bottom": (String(localized: "Scroll to the bottom", bundle: .module), String(localized: "Jump back to the newest line when you type, or when output arrives.", bundle: .module)),
        "mouse-reporting": (String(localized: "Send the mouse to programs", bundle: .module), String(localized: "Let programs such as vim or tmux receive clicks and scrolling when they ask for them.", bundle: .module)),
        "right-click-action": (String(localized: "Right-click", bundle: .module), nil),
        "middle-click-action": (String(localized: "Middle-click", bundle: .module), nil),
        "click-repeat-interval": (String(localized: "Double-click interval", bundle: .module), String(localized: "Milliseconds between clicks of a double or triple click; 0 follows the system.", bundle: .module)),
        "selection-word-chars": (String(localized: "Word boundaries", bundle: .module), String(localized: "Characters where selecting a word by double-clicking stops.", bundle: .module)),
        "macos-option-as-alt": (String(localized: "Use Option as Alt", bundle: .module), String(localized: "Option sends Alt sequences to programs instead of typing special characters. By default this follows the keyboard layout.", bundle: .module)),
        "alpha-blending": (String(localized: "Blending color space", bundle: .module), String(localized: "How translucent colors and the edges of text are blended.", bundle: .module)),
        "window-colorspace": (String(localized: "Color space", bundle: .module), String(localized: "How colors set here and by programs are read.", bundle: .module)),
        "title-report": (String(localized: "Let programs read the title", bundle: .module), String(localized: "Answer programs that ask for the session title, which can hold private text.", bundle: .module)),
        "osc-color-report-format": (String(localized: "Color report format", bundle: .module), String(localized: "How the terminal answers programs that ask for its colors.", bundle: .module)),
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
        "font-shaping-break": ["cursor": String(localized: "Under the cursor", bundle: .module)],
        "scroll-to-bottom": ["keystroke": String(localized: "On typing", bundle: .module),
        "output": String(localized: "On output", bundle: .module)],
        "right-click-action": ["context-menu": String(localized: "Show the menu", bundle: .module),
        "copy-or-paste": String(localized: "Copy, or paste without a selection", bundle: .module),
        "copy": String(localized: "Copy", bundle: .module),
        "paste": String(localized: "Paste", bundle: .module),
        "ignore": String(localized: "Nothing", bundle: .module)],
        "middle-click-action": ["primary-paste": String(localized: "Paste the selection", bundle: .module),
        "ignore": String(localized: "Nothing", bundle: .module)],
        "macos-option-as-alt": ["true": String(localized: "Both Option keys", bundle: .module),
        "false": String(localized: "Neither", bundle: .module),
        "left": String(localized: "Left Option key", bundle: .module),
        "right": String(localized: "Right Option key", bundle: .module)],
        "alpha-blending": ["native": String(localized: "Native", bundle: .module),
        "linear": String(localized: "Linear", bundle: .module),
        "linear-corrected": String(localized: "Linear, corrected for text", bundle: .module)],
        "osc-color-report-format": ["none": String(localized: "Don't answer", bundle: .module)],
    ]

    static func optionName(_ key: String, value: String, fallback: String) -> String {
        optionNames[key]?[value] ?? fallback
    }
}
