import XCTest
@testable import RayonTerminal

final class ConfigurationTests: XCTestCase {
    func testCatalogCoversEverySettingExactlyOnce() {
        let catalog = ConfigCatalog.shared
        XCTAssertEqual(catalog.registry.count, 200)
        XCTAssertEqual(catalog.themes.count, 633)
        let ids = catalog.navigation.flatMap(\.settingIDs)
        XCTAssertEqual(Set(ids), Set(catalog.registry.keys))
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(catalog.registry["quitAfterLastWindowClosed"]?.defaultValue, .scalar("false"))
    }
    func testSettingsLayoutShowsEveryAppliedSettingOnce() {
        let keys = ConfigLayout.categories.flatMap(\.keys)
        XCTAssertEqual(keys.count, Set(keys).count, "a setting appears in two places")
        XCTAssertEqual(Set(keys), ConfigCatalog.rayonKeys, "Settings and the applied keys disagree")
        for key in keys {
            XCTAssertNotNil(ConfigCatalog.shared.setting(key: key), "\(key) is not in the catalog")
        }
        XCTAssertEqual(ConfigLayout.categories.map(\.id).count, Set(ConfigLayout.categories.map(\.id)).count)
    }
    func testShortcutsReadAsKeyCaps() {
        XCTAssertEqual(KeybindingNames.step("super+shift+k"), "⇧⌘K")
        XCTAssertEqual(KeybindingNames.step("super+physical:four"), "⌘4")
        XCTAssertEqual(KeybindingNames.step("ctrl+alt+arrow_left"), "⌃⌥←")
        XCTAssertEqual(KeybindingNames.step("super+equal"), "⌘=")
        XCTAssertEqual(KeybindingNames.summary(ConfigKeybinding("super+equal=increase_font_size:1")), "Make Text Bigger (1 pt)")
        XCTAssertEqual(KeybindingNames.summary(ConfigKeybinding("super+backspace=text:\\x15")), "Delete to Start of Line")
        XCTAssertEqual(KeybindingNames.summary(ConfigKeybinding("alt+arrow_left=esc:b")), "Move Back a Word")
        XCTAssertFalse(KeybindingNames.applies(ConfigKeybinding("super+t=new_tab")))
        XCTAssertTrue(KeybindingNames.applies(ConfigKeybinding("super+k=clear_screen")))
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
    func testEditorShowsRayonRuntimeDefaults() {
        let document = ConfigDocument()
        XCTAssertEqual(document.text("font-size"), "14")
        XCTAssertEqual(document.text("font-thicken"), "true")
        XCTAssertEqual(document.text("cursor-style-blink"), "true")
        XCTAssertEqual(document.text("minimum-contrast"), ConfigCatalog.shared.setting(key: "minimum-contrast")?.defaultValue.text)
    }
    func testImportMergePaletteRepeatableAndScalar() throws {
        var draft = ConfigDocument()
        try draft.merge("font-size = 17\nfont-family = Mono\nfont-family = 日本語\npalette = 2=#112233\nkeybind = ctrl+k=text:a=b:c")
        try draft.merge("font-size = 19\npalette = 3=#334455\nfont-family = Other\nkeybind = ctrl+x=ignore")
        XCTAssertEqual(draft.text("font-size"), "19")
        XCTAssertEqual(draft.values("font-family"), ["Other"])
        XCTAssertEqual(draft.paletteOverrides, [2: "#112233", 3: "#334455"])
        XCTAssertEqual(Array(draft.values("keybind").suffix(2)), ["ctrl+k=text:a=b:c", "ctrl+x=ignore"])
        let original = draft
        XCTAssertThrowsError(try draft.merge("font-size = 22\npalette = broken"))
        XCTAssertEqual(original, draft)
    }
    func testThemesDoNotContaminateDiffAndExplicitColorsWin() throws {
        var draft = ConfigDocument()
        draft.set("theme", ["light:3024 Day,dark:3024 Night"])
        XCTAssertEqual(draft.effectiveColor("background", dark: false), "#f7f7f7")
        XCTAssertEqual(draft.effectiveColor("background", dark: true), "#090300")
        XCTAssertFalse(draft.serialized().contains("background ="))
        draft.set("background", ["#123456"])
        XCTAssertEqual(draft.effectiveColor("background", dark: true), "#123456")
        draft.setPalette(255, color: "#010203")
        XCTAssertTrue(draft.serialized().contains("palette = 255=#010203"))
        draft.setPalette(255, color: nil)
        XCTAssertFalse(draft.serialized().contains("palette ="))
    }
    func testUnicodeSharingAndLargeFallback() throws {
        var draft = ConfigDocument()
        try draft.merge("font-family = 日本語\nkeybind = ctrl++=text:a=b:c\nfuture-key = one\nfuture-key = two")
        let url = try XCTUnwrap(draft.shareURL())
        XCTAssertFalse(url.contains("=="))
        var imported = ConfigDocument()
        try imported.merge(url)
        XCTAssertEqual(imported, draft)
        draft.set("title", [String(repeating: "大", count: 1000)])
        XCTAssertNil(draft.shareURL())
        XCTAssertThrowsError(try ConfigDocument.decodeShareOrText("https://ghostty.zerebos.com/#share=%%%"))
    }
}
