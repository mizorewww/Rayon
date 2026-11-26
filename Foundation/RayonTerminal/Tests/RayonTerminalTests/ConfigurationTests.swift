import GhosttyTerminal
import XCTest
@testable import RayonTerminal

final class ConfigurationTests: XCTestCase {
    func testSettingAKeyKeepsEverythingElseAsWritten() throws {
        var config = GhosttyConfigText("# mine\nfont-size = 13\n\nkeybind = ctrl+a=text:a\nkeybind = ctrl+b=text:b\nfont-family = \"Menlo\"\n")
        XCTAssertEqual(config.value("font-family"), "Menlo")
        XCTAssertEqual(config.values("keybind"), ["ctrl+a=text:a", "ctrl+b=text:b"])

        config.set("keybind", ["ctrl+c=text:c"])
        config.set("font-size", ["15"])
        config.set("theme", ["Dracula"])
        config.set("font-family", [])
        XCTAssertEqual(config.text, "# mine\nfont-size = 15\n\nkeybind = ctrl+c=text:c\ntheme = Dracula\n")

        XCTAssertThrowsError(try GhosttyConfigText("font-size = 13\nnot a setting").entries())
    }

    func testThemeNamesForOneOrBothAppearances() {
        XCTAssertTrue(RayonTerminalConfiguration.themeNames("Dracula") == ("Dracula", "Dracula"))
        XCTAssertTrue(RayonTerminalConfiguration.themeNames("light:Alabaster, dark:Dracula") == ("Alabaster", "Dracula"))
    }

    /// Explicit lines win over the theme, the app's clipboard policy over
    /// the file, and a configuration Ghostty rejects changes nothing.
    @MainActor
    func testApplyLayersThemeFileAndClipboardPolicy() throws {
        let controller = TerminalController(configuration: .default)
        let config = GhosttyConfigText("theme = Dracula\nbackground = #223344\nclipboard-write = allow\n")
        try RayonTerminalConfiguration.apply(config, to: controller)
        let dark = controller.theme.dark.rendered
        XCTAssertNotNil(dark.range(of: "background = #223344", options: .backwards))
        XCTAssertGreaterThan(
            dark.range(of: "background = #223344")!.lowerBound,
            dark.range(of: "background = ")!.lowerBound,
            "The file's background comes after the theme's"
        )
        XCTAssertFalse(dark.contains("theme ="))
        XCTAssertTrue(dark.hasSuffix("clipboard-write = \(RayonTerminalConfiguration.clipboardSharing ? "allow" : "deny")"))

        let before = controller.theme
        XCTAssertThrowsError(try RayonTerminalConfiguration.apply(GhosttyConfigText("font-size = big"), to: controller))
        XCTAssertThrowsError(try RayonTerminalConfiguration.apply(GhosttyConfigText("theme = No Such Theme"), to: controller))
        XCTAssertEqual(controller.theme, before)
    }

    /// Saving writes the file only after Ghostty accepts it, and every
    /// terminal, open or new, takes the new font size.
    @MainActor
    func testSaveAppliesToOpenTerminalsAndWritesTheFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = RayonTerminalConfiguration.fileURL
        let originalContents = RayonTerminalConfiguration.contents
        RayonTerminalConfiguration.fileURL = folder.appendingPathComponent("config.ghostty")
        defer {
            try? RayonTerminalConfiguration.save(originalContents)
            RayonTerminalConfiguration.fileURL = original
            try? FileManager.default.removeItem(at: folder)
        }

        TestHost.prepare()
        let terminal = RayonTerminalView()
        let native = terminal.session.platformView()
        let window = TestHost(native)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        terminal.write("configuration survival marker\r\n")
        XCTAssertTrue(terminal.session.backend.waitForPendingOutput())

        var reported: Double?
        RayonTerminalConfiguration.onFontSizeChange = { reported = $0 }
        defer { RayonTerminalConfiguration.onFontSizeChange = nil }
        try RayonTerminalConfiguration.save("font-size = 13.5\ntheme = 3024 Night\n")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(native.fontSize, 13.5)
        XCTAssertEqual(reported, 13.5)
        XCTAssertTrue(terminal.session.backend.readViewportText()?.contains("configuration survival marker") == true)
        XCTAssertEqual(try String(contentsOf: RayonTerminalConfiguration.fileURL, encoding: .utf8), "font-size = 13.5\ntheme = 3024 Night\n")

        XCTAssertThrowsError(try RayonTerminalConfiguration.save("font-size = big"))
        XCTAssertEqual(RayonTerminalConfiguration.contents, "font-size = 13.5\ntheme = 3024 Night\n")

        let next = RayonTerminalView()
        let second = TestHost(next.session.platformView())
        defer { second.close() }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(next.session.platformView().fontSize, 13.5)
    }

    @MainActor
    func testSyncSeesAndAdoptsKeys() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = RayonTerminalConfiguration.fileURL
        let originalContents = RayonTerminalConfiguration.contents
        RayonTerminalConfiguration.fileURL = folder.appendingPathComponent("config.ghostty")
        defer {
            try? RayonTerminalConfiguration.save(originalContents)
            RayonTerminalConfiguration.fileURL = original
            try? FileManager.default.removeItem(at: folder)
        }
        try RayonTerminalConfiguration.save("font-size = 12\nkeybind = ctrl+a=text:a\n")
        TerminalConfigurationSync.adopt(["font-size": nil, "cursor-style": ["bar"]])
        XCTAssertEqual(TerminalConfigurationSync.overrides, ["keybind": ["ctrl+a=text:a"], "cursor-style": ["bar"]])
    }
}
