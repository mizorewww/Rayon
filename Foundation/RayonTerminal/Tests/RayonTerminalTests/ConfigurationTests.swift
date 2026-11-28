import XCTest
@testable import RayonTerminal

final class ConfigurationTests: XCTestCase {
    /// Every Ghostty option the catalog has is in exactly one place in
    /// Settings, so none can be lost from it.
    func testEverySettingIsReachableExactlyOnce() {
        let catalog = SettingCatalog.shared
        XCTAssertEqual(catalog.settings.count, 86)
        let keys = SettingsLayout.categories.flatMap(\.keys)
        XCTAssertEqual(keys.count, Set(keys).count, "a setting appears in two places")
        XCTAssertEqual(Set(keys), Set(catalog.settings.map(\.key)), "Settings and the catalog disagree")
        for key in keys { XCTAssertNotNil(catalog.setting(key), "\(key) is not in the catalog") }
        XCTAssertEqual(SettingsLayout.categories.map(\.id).count, Set(SettingsLayout.categories.map(\.id)).count)
        XCTAssertEqual(catalog.setting("title-report")?.defaultValue, .scalar("false"))
        XCTAssertEqual(RayonTerminalConfiguration.supportedKeys.union(["theme"]), Set(keys))
    }

    /// Each setting gets a control from its catalog entry.
    func testEverySettingHasAControl() {
        for setting in SettingCatalog.shared.settings {
            let kind = SettingControlKind(setting)
            if case let .choice(options) = kind { XCTAssertFalse(options.isEmpty, setting.key) }
            if case let .flags(features) = kind { XCTAssertFalse(features.isEmpty, setting.key) }
        }
        XCTAssertNotNil(SettingCatalog.shared.setting("cursor-color").map(SettingControlKind.init).flatMap { kind -> Bool? in
            if case .color = kind { return true } else { return nil }
        })
    }

    /// Every setting Settings shows has Rayon's title and summary, and every
    /// choice, preset, flag and field label its control shows has Rayon's
    /// name, so none falls back to the catalog's English. Rayon's wording is
    /// all `String(localized:)`, which `make check-localization` holds to a
    /// translation in every language.
    func testEverySettingShownIsWordedByRayon() {
        // Technical names that read the same in every language.
        let verbatim: [String: Set<String>] = [
            "window-colorspace": ["srgb", "display-p3"],
            "osc-color-report-format": ["8-bit", "16-bit"],
        ]
        let keys = SettingsLayout.categories.flatMap(\.keys)
        for key in keys {
            guard let setting = SettingCatalog.shared.setting(key) else { XCTFail("\(key) is not in the catalog"); continue }
            let wording = SettingsLayout.wording[key]
            XCTAssertNotNil(wording, "\(key) has no localized title and summary")
            XCTAssertFalse(wording?.title.isEmpty ?? true, key)
            XCTAssertFalse(wording?.summary.isEmpty ?? true, key)
            let widget = setting.widget
            let named = (widget?.options ?? []).map(\.value) + (widget?.presets ?? []).map(\.value)
                + (widget?.features ?? []).map(\.id) + (widget?.labels ?? [])
            for value in named where verbatim[key]?.contains(value) != true {
                XCTAssertNotNil(SettingsLayout.optionNames[key]?[value], "\(key): \"\(value)\" has no localized name")
            }
            switch SettingControlKind(setting) {
            case .text, .list:
                XCTAssertNil(widget?.placeholder, "\(key) shows the catalog's English placeholder")
            case let .choice(options), let .color(options), let .number(_, _, _, options):
                for option in options where verbatim[key]?.contains(option.value) != true {
                    XCTAssertEqual(option.name, SettingsLayout.optionNames[key]?[option.value], "\(key) shows the catalog's name")
                }
            case let .flags(features):
                for feature in features {
                    XCTAssertEqual(feature.label, SettingsLayout.optionNames[key]?[feature.id], "\(key) shows the catalog's name")
                }
            case let .pair(labels):
                XCTAssertEqual(labels, widget?.labels?.compactMap { SettingsLayout.optionNames[key]?[$0] }, "\(key) shows the catalog's labels")
            default:
                break
            }
        }
        XCTAssertEqual(Set(SettingsLayout.wording.keys).subtracting(keys), [], "wording for a setting Settings no longer shows")
        XCTAssertEqual(Set(SettingsLayout.optionNames.keys).subtracting(keys), [], "names for a setting Settings no longer shows")
    }

    /// No theme offered before is lost: GhosttyTheme's and the supplement's together.
    func testThemes() throws {
        let names = TerminalThemes.all.map(\.name)
        XCTAssertEqual(names.count, 633)
        XCTAssertEqual(names.count, Set(names).count)
        let day = try XCTUnwrap(TerminalThemes.theme(for: "light:3024 Day,dark:3024 Night", dark: false))
        XCTAssertEqual(day.color("background"), "#f7f7f7")
        XCTAssertEqual(TerminalThemes.theme(for: "light:3024 Day,dark:3024 Night", dark: true)?.color("background"), "#090300")
        for theme in TerminalThemes.all {
            XCTAssertNotNil(theme.paletteColor(15), theme.name)
        }
    }

    /// The themes GhosttyTheme defines otherwise look as they did before.
    func testThemesLookAsTheyDidBefore() throws {
        let before: [String: (background: String, selection: String?, color8: String?)] = [
            "Adwaita": ("#ffffff", "#1d1d20", "#5d5d5d"),
            "Adwaita Dark": ("#1c1c1f", "#ffffff", "#5e5c64"),
            "Catppuccin Frappe": ("#303446", "#f2d5cf", "#626880"),
            "Catppuccin Latte": ("#eff1f5", "#dc8a78", "#acb0be"),
            "Catppuccin Macchiato": ("#24273a", "#f4dbd6", "#5b6078"),
            "Catppuccin Mocha": ("#1e1e2e", "#f5e0dc", "#585b70"),
            "Dark Modern": ("#1f1f1f", "#3a3d41", "#666666"),
            "Electron Highlighter": ("#23283d", "#293257", "#4b5b8c"),
        ]
        for (name, colors) in before {
            let theme = try XCTUnwrap(TerminalThemes.theme(named: name), name)
            XCTAssertEqual(theme.color("background"), colors.background, name)
            XCTAssertEqual(theme.color("selection-background"), colors.selection, name)
            XCTAssertEqual(theme.paletteColor(8), colors.color8, name)
        }
    }

    func testGhosttyConfigTextKeepsOnlyCatalogOptions() {
        let parsed = GhosttyConfigImport.parse("# font-size = 1\nfont-size = 12\n\nbroken line\nunknown-future = x\nwindow-decoration = none\nkeybind = a=ignore\nkeybind = b=ignore\nbackground = #111111\nbackground =\n")
        XCTAssertEqual(parsed.values, ["font-size": ["12"], "keybind": ["a=ignore", "b=ignore"]])
        XCTAssertEqual(parsed.skipped, ["unknown-future", "window-decoration"])
    }

    func testShortcutsReadAsKeyCaps() {
        XCTAssertEqual(KeybindingNames.step("super+shift+k"), "⇧⌘K")
        XCTAssertEqual(KeybindingNames.step("super+physical:four"), "⌘4")
        XCTAssertEqual(KeybindingNames.step("ctrl+alt+arrow_left"), "⌃⌥←")
        XCTAssertEqual(KeybindingNames.step("super+equal"), "⌘=")
        XCTAssertEqual(KeybindingNames.summary(Keybinding("super+equal=increase_font_size:1")), "Make Text Bigger (1 pt)")
        XCTAssertEqual(KeybindingNames.summary(Keybinding("super+backspace=text:\\x15")), "Delete to Start of Line")
        XCTAssertEqual(KeybindingNames.summary(Keybinding("alt+arrow_left=esc:b")), "Move Back a Word")
        XCTAssertFalse(KeybindingNames.applies(Keybinding("super+t=new_tab")))
        XCTAssertTrue(KeybindingNames.applies(Keybinding("super+k=clear_screen")))
    }

    func testCodepointMappingRoundTrip() {
        let mapping = CodepointMapping("U+E000-U+F8FF,U+F0000-U+FFFFD=Symbols Nerd Font")
        XCTAssertEqual(mapping?.family, "Symbols Nerd Font")
        XCTAssertEqual(CodepointRangeSet.describe(mapping?.ranges ?? ""), "Nerd Font icons")
        XCTAssertEqual(mapping?.rendered, "U+E000-U+F8FF,U+F0000-U+FFFFD=Symbols Nerd Font")
        XCTAssertEqual(CodepointRangeSet.describe("U+1234"), "U+1234")
    }

    @MainActor func testInstalledFontsComeFromCoreText() {
        XCTAssertTrue(FontLibrary.isMonospaced("Menlo"))
        XCTAssertFalse(FontLibrary.styles(of: "Menlo").isEmpty)
        XCTAssertFalse(FontLibrary.families.contains { $0.name.hasPrefix(".") })
    }

    @MainActor func testSettingsShowRayonRuntimeDefaults() {
        // Ghostty's built-in size differs per platform.
        #if os(macOS)
            XCTAssertEqual(TerminalSettings.defaultValues("font-size"), ["14"])
        #else
            XCTAssertEqual(TerminalSettings.defaultValues("font-size"), ["10"])
        #endif
        XCTAssertEqual(TerminalSettings.defaultValues("font-thicken"), ["true"])
        XCTAssertEqual(TerminalSettings.defaultValues("cursor-style-blink"), ["true"])
        XCTAssertEqual(TerminalSettings.defaultValues("minimum-contrast"), SettingCatalog.shared.setting("minimum-contrast")?.defaultValue.values)
    }

    func testCompoundValues() throws {
        XCTAssertEqual(DurationValue.describe(try DurationValue.parse("1h30m", allowEmpty: false)), "1 hour, 30 minutes")
        XCTAssertEqual(try DurationValue.parse("4ms", allowEmpty: false).first?.1, "ms")
        XCTAssertThrowsError(try DurationValue.parse("1s2s", allowEmpty: false))
        XCTAssertThrowsError(try DurationValue.parse("-1m", allowEmpty: false))
        XCTAssertThrowsError(try DurationValue.parse("1.5s", allowEmpty: false))
        XCTAssertTrue(try DurationValue.parse("", allowEmpty: true).isEmpty)
        for valid in ["liga", "-liga", "+calt", "ss07", "cv01=2", "cv01 2", "liga on", "liga OFF", "\"kern\" = 0", "liga, -calt"] {
            XCTAssertNoThrow(try FontFeatureValue.validate(valid), valid)
        }
        for invalid in ["!!=bad value", "lig", "-liga=0", "liga=x", "liga 2 ", "ligatures", "liga of"] {
            XCTAssertThrowsError(try FontFeatureValue.validate(invalid), invalid)
        }
        XCTAssertEqual(PairValue.parse("discrete:3,precision:1", scroll: true).values, ["1", "3"])
        XCTAssertEqual(PairValue.parse("precision:2", scroll: true).values, ["2", "3"])
        XCTAssertFalse(PairValue.parse("precision:2", scroll: true).linked)
        XCTAssertEqual(PairValue.parse("", scroll: true).values, ["1", "3"])
        XCTAssertTrue(PairValue.parse("2", scroll: false).linked)
        XCTAssertEqual(PairValue.render("2", "4", linked: false, scroll: false), "2,4")
        XCTAssertEqual(LengthValue.render("120", percent: true), "120%")
        XCTAssertEqual(LengthValue.parse("120%").number, "120")
        XCTAssertEqual(1234.5.configText, "1234.5")
        XCTAssertEqual(0.30000000000000004.configText, "0.3")
    }
}
