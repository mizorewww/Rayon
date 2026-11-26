import XCTest
@testable import RayonTerminal

final class ConfigurationTests: XCTestCase {
    /// Every Ghostty option the catalog has is in exactly one place in
    /// Settings, so none can be lost from it.
    func testEverySettingIsReachableExactlyOnce() {
        let catalog = SettingCatalog.shared
        XCTAssertEqual(catalog.settings.count, 200)
        let keys = SettingsLayout.categories.flatMap(\.keys)
        XCTAssertEqual(keys.count, Set(keys).count, "a setting appears in two places")
        XCTAssertEqual(Set(keys), Set(catalog.settings.map(\.key)), "Settings and the catalog disagree")
        for key in keys { XCTAssertNotNil(catalog.setting(key), "\(key) is not in the catalog") }
        XCTAssertEqual(SettingsLayout.categories.map(\.id).count, Set(SettingsLayout.categories.map(\.id)).count)
        XCTAssertEqual(catalog.setting("quit-after-last-window-closed")?.defaultValue, .scalar("false"))
    }

    /// The categories Rayon's terminal reads hold exactly the keys it applies;
    /// the others are under Ghostty App.
    func testAppliedSettingsAreOutsideGhosttyApp() throws {
        let ghostty = try XCTUnwrap(SettingsLayout.category(SettingsLayout.Category.ghosttyID))
        let applied = Set(SettingsLayout.categories.filter { $0.id != ghostty.id }.flatMap(\.keys))
        XCTAssertEqual(applied, RayonTerminalConfiguration.supportedKeys.union(["theme"]))
        XCTAssertTrue(Set(ghostty.keys).isDisjoint(with: RayonTerminalConfiguration.supportedKeys))
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

    func testConfigTextKeepsWhatItDoesNotTouch() throws {
        var text = GhosttyConfigText("# mine\nfont-size = 12\n\nunknown-future = x\nkeybind = a=ignore\nkeybind = b=ignore\n")
        text.set("keybind", ["c=ignore"])
        text.set("font-size", ["13"])
        text.set("background", ["#123456"])
        XCTAssertEqual(text.text, "# mine\nfont-size = 13\n\nunknown-future = x\nkeybind = c=ignore\nbackground = #123456\n")
        text.set("unknown-future", [])
        XCTAssertEqual(text.values("unknown-future"), [])
        XCTAssertEqual(try text.entries().count, 3)
        XCTAssertThrowsError(try GhosttyConfigText("palette broken").entries())
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
