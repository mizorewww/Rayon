import GhosttyTerminal
import XCTest
@testable import RayonTerminal

final class ConfigurationRuntimeTests: XCTestCase {
    func testKeybindingGrammarAndArguments() {
        XCTAssertTrue(Keybinding("ctrl++=text:a=b:c").errors.isEmpty)
        XCTAssertTrue(Keybinding("+=ignore").errors.isEmpty)
        XCTAssertEqual(Keybinding("ctrl++=text:a=b:c").argument, "a=b:c")
        XCTAssertEqual(Keybinding("unconsumed:cmd+ctrl+k=ignore").canonical,
                       Keybinding("control+super+k=ignore").canonical)
        XCTAssertTrue(Keybinding("super+ArrowUp=scroll_to_top").errors.isEmpty)
        XCTAssertFalse(Keybinding("global:super+k>c=ignore").errors.isEmpty)
        XCTAssertFalse(Keybinding("ctrl+k=goto_tab:0").errors.isEmpty)
        XCTAssertFalse(Keybinding("ctrl+k=resize_split:sideways,-1").errors.isEmpty)
        XCTAssertEqual(KeybindingCatalog.shared.actions.count, 83)
    }

    /// A file of its own and a clean shared terminal configuration afterwards.
    @MainActor private func scratchSettings(_ text: String? = nil, defaults: UserDefaults = .standard) throws -> TerminalSettings {
        let url = FileManager.default.temporaryDirectory.appending(path: "RayonTerminalTests-\(UUID())/config.ghostty")
        if let text {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        addTeardownBlock { @MainActor in
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            try? RayonTerminalConfiguration.apply(TerminalSettings.shared.applied)
        }
        return TerminalSettings(fileURL: url, defaults: defaults)
    }

    @MainActor func testExplicitGhosttyDefaultOverridesRayonDefault() throws {
        let size = try XCTUnwrap(SettingCatalog.shared.setting("font-size")?.defaultValue.values.first)
        let text = try RayonTerminalConfiguration.contents(GhosttyConfigText("font-size = \(size)\nfont-thicken = false"), dark: true)
        XCTAssertTrue(text.contains("font-size = \(size)"))
        let lines = text.components(separatedBy: "\n")
        XCTAssertGreaterThan(try XCTUnwrap(lines.lastIndex(of: "font-thicken = false")), try XCTUnwrap(lines.lastIndex(of: "font-thicken = true")))
    }

    @MainActor func testRuntimeFilterAndDualThemes() throws {
        TestHost.prepare()
        let config = GhosttyConfigText("theme = light:3024 Day,dark:3024 Night\nbackground = #223344\ncommand = rm -rf /\nconfig-file = /tmp/config\nclipboard-write = deny\nkeybind = global:ctrl+k=quit\nkeybind = ctrl+k=text:hello")
        let text = try RayonTerminalConfiguration.contents(config, dark: true)
        XCTAssertFalse(text.contains("command ="))
        XCTAssertFalse(text.contains("config-file ="))
        // A user's clipboard-write is filtered out: the only such line is the
        // one the app's sharing preference appends.
        XCTAssertFalse(text.contains("clipboard-write = deny"))
        XCTAssertFalse(text.contains("=quit"))
        XCTAssertTrue(text.contains("ctrl+k=text:hello"))
        XCTAssertTrue(text.contains("background = #090300"))
        XCTAssertTrue(try RayonTerminalConfiguration.contents(config, dark: false).contains("background = #f7f7f7"))
        let controller = TerminalController(configuration: RayonTerminalConfiguration.base)
        try RayonTerminalConfiguration.apply(config, to: controller)
        let before = controller.theme
        var broken = config
        broken.set("font-size", ["not a number"])
        XCTAssertThrowsError(try RayonTerminalConfiguration.apply(broken, to: controller))
        XCTAssertEqual(controller.theme, before)
        XCTAssertThrowsError(try RayonTerminalConfiguration.apply(GhosttyConfigText("not a line"), to: controller))
        // Ghostty takes any font feature and drops the ones it cannot read.
        XCTAssertThrowsError(try RayonTerminalConfiguration.apply(GhosttyConfigText("font-feature = !!=bad value"), to: controller))
    }

    /// The shortcut list as written replaces Ghostty's: a default deleted in
    /// Settings stays deleted.
    @MainActor func testDeletedDefaultShortcutIsUnbound() throws {
        let settings = try scratchSettings()
        let defaults = settings.shortcuts
        XCTAssertFalse(defaults.isEmpty)
        XCTAssertFalse(settings.config.values("keybind").contains("clear"))
        settings.setShortcuts(Array(defaults.dropFirst()) + ["ctrl+k=text:hello"])
        XCTAssertEqual(settings.shortcuts, Array(defaults.dropFirst()) + ["ctrl+k=text:hello"])
        XCTAssertEqual(settings.config.values("keybind").first, "clear")
        let text = try RayonTerminalConfiguration.contents(settings.config, dark: true)
        XCTAssertTrue(text.contains("keybind = clear"))
        try RayonTerminalConfiguration.apply(settings.config, to: TerminalController(configuration: .default))
    }

    @MainActor func testFindBarKeysAreNotGhosttys() throws {
        for config in [GhosttyConfigText(), GhosttyConfigText("keybind = ctrl+k=ignore")] {
            let text = try RayonTerminalConfiguration.contents(config, dark: false)
            for trigger in RayonTerminalConfiguration.unboundTriggers {
                XCTAssertTrue(text.contains("keybind = \(trigger)=unbind"), trigger)
            }
            let controller = TerminalController(configuration: RayonTerminalConfiguration.base)
            try RayonTerminalConfiguration.apply(config, to: controller)
            XCTAssertNil(controller.lastConfigurationIssue)
        }
        // The shared controller has them before any setting is applied.
        XCTAssertTrue(TerminalController(configuration: RayonTerminalConfiguration.base).renderedConfig.contains("keybind = escape=unbind"))
    }

    @MainActor func testApplyPreservesSurfaceAndFractionalFontForNewSessions() async throws {
        TestHost.prepare()
        defer { try? RayonTerminalConfiguration.apply(TerminalSettings.shared.applied) }
        let terminal = RayonTerminalView()
        let native = terminal.session.platformView()
        let window = TestHost(native)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        terminal.write("configuration survival marker\r\n")
        XCTAssertTrue(terminal.session.backend.waitForPendingOutput())
        try RayonTerminalConfiguration.apply(GhosttyConfigText("font-size = 13.5\ntheme = 3024 Night"))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(native === terminal.session.platformView())
        XCTAssertEqual(native.fontSize, 13.5)
        XCTAssertTrue(terminal.session.backend.readViewportText()?.contains("configuration survival marker") == true)
        terminal.setTerminalFontSize(with: 14, preferConfigured: true)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(native.fontSize, 13.5)
        // A fresh batch/interactive view shares the same exact (non-rounded) configuration.
        let next = RayonTerminalView()
        let second = TestHost(next.session.platformView())
        defer { second.close() }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(next.session.platformView().fontSize, 13.5)
        // Explicit legacy toolbar zoom still changes the current surface.
        terminal.setTerminalFontSize(with: 20)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(native.fontSize, 20)
        terminal.setTerminalFontSize(with: 20, preferConfigured: true)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(native.fontSize, 20, "Reappearance must preserve local toolbar zoom")
    }
    @MainActor func testChangesApplySaveAndUndo() throws {
        let settings = try scratchSettings("# kept\nfuture-key = 1\n")
        settings.set("background", "#123456")
        XCTAssertTrue(settings.applyNow())
        XCTAssertEqual(try String(contentsOf: settings.fileURL, encoding: .utf8), "# kept\nfuture-key = 1\nbackground = #123456\n")
        settings.undo()
        XCTAssertFalse(settings.isSet("background"))
        settings.redo()
        XCTAssertEqual(settings.value("background"), "#123456")
        XCTAssertTrue(settings.applyNow())
        // A value Ghostty rejects is shown but neither applied nor saved.
        settings.set("font-size", "not a number")
        XCTAssertFalse(settings.applyNow())
        XCTAssertNotNil(settings.issue)
        XCTAssertEqual(settings.applied.values("font-size"), [])
        XCTAssertFalse(try String(contentsOf: settings.fileURL, encoding: .utf8).contains("font-size"))
        settings.resetAll()
        XCTAssertTrue(settings.applyNow())
        XCTAssertNil(settings.issue)
        XCTAssertEqual(try String(contentsOf: settings.fileURL, encoding: .utf8), "# kept\nfuture-key = 1\n")
    }

    @MainActor func testPaletteAndEffectiveColors() throws {
        let settings = try scratchSettings("theme = light:3024 Day,dark:3024 Night\n")
        XCTAssertEqual(settings.effectiveColor("background", dark: false), "#f7f7f7")
        XCTAssertEqual(settings.effectiveColor("background", dark: true), "#090300")
        settings.set("background", "#123456")
        XCTAssertEqual(settings.effectiveColor("background", dark: true), "#123456")
        settings.setPalette(255, "#010203")
        settings.setPalette(2, "#112233")
        XCTAssertEqual(settings.config.values("palette"), ["2=#112233", "255=#010203"])
        XCTAssertEqual(settings.effectivePalette(255, dark: true), "#010203")
        settings.setPalette(255, nil)
        settings.setPalette(2, nil)
        XCTAssertFalse(settings.isSet("palette"))
    }

    /// Settings the previous release kept in the user defaults become config.ghostty.
    @MainActor func testLegacySettingsMoveToTheFile() throws {
        let suite = "RayonConfigurationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = #"{"document":{"overrides":{"font-size":["15"],"keybind":["ctrl+k=ignore"],"palette":["1=#010101"]}}}"#
        defaults.set(Data(legacy.utf8), forKey: "me.mizorewww.rayon.ghosttyConfiguration.v1")
        let settings = try scratchSettings(defaults: defaults)
        XCTAssertEqual(settings.value("font-size"), "15")
        XCTAssertEqual(settings.shortcuts, ["ctrl+k=ignore"])
        XCTAssertEqual(settings.paletteOverrides, [1: "#010101"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: settings.fileURL.path))
        XCTAssertNil(defaults.data(forKey: "me.mizorewww.rayon.ghosttyConfiguration.v1"))
    }

    /// Every shortcut removed in the previous release stays removed: Ghostty's
    /// defaults do not come back.
    @MainActor func testAnEmptyLegacyShortcutListStaysEmpty() throws {
        let suite = "RayonConfigurationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = #"{"document":{"overrides":{"keybind":[],"palette":[]}}}"#
        defaults.set(Data(legacy.utf8), forKey: "me.mizorewww.rayon.ghosttyConfiguration.v1")
        let settings = try scratchSettings(defaults: defaults)
        XCTAssertEqual(settings.applied.text, "keybind = clear\n")
    }

    /// What another device set is applied at once, keeps local lines, and is
    /// not something Undo takes back.
    @MainActor func testAdoptingRemoteChanges() throws {
        let settings = try scratchSettings("# mine\nfont-size = 16\n")
        settings.adopt(["background": ["#222222"], "font-size": nil])
        XCTAssertEqual(settings.applied.text, "# mine\nbackground = #222222\n")
        XCTAssertFalse(settings.undoManager.canUndo)
        settings.adopt(["font-size": ["not a number"]])
        XCTAssertNotNil(settings.issue)
        XCTAssertEqual(settings.applied.values("font-size"), [])
    }

    /// What syncs leaves the device's own keys, comments and unknown keys
    /// alone, both ways.
    @MainActor func testSyncCarriesAllButDeviceBoundKeys() throws {
        let settings = try scratchSettings("# mine\nfont-size = 16\nwindow-padding-x = 4\nbackground = #111111\nfuture-key = 1\nkeybind = clear\nkeybind = ctrl+k=ignore\n")
        XCTAssertEqual(TerminalConfigurationSync.entries(of: settings), [
            "background": ["#111111"], "keybind": ["clear", "ctrl+k=ignore"],
        ])
        let remote = ["foreground": ["#eeeeee"], "keybind": ["clear", "ctrl+j=ignore"], "font-size": ["30"], "window-padding-y": ["9"]]
        let expected: [String: [String]?] = [
            "background": nil as [String]?, "foreground": ["#eeeeee"], "keybind": ["clear", "ctrl+j=ignore"],
        ]
        XCTAssertEqual(try TerminalConfigurationSync.changes(from: XCTUnwrap(TerminalConfigurationSync.entries(of: settings)), to: remote), expected)
        TerminalConfigurationSync.adopt(remote, into: settings)
        XCTAssertEqual(settings.applied.text, "# mine\nfont-size = 16\nwindow-padding-x = 4\nfuture-key = 1\nkeybind = clear\nkeybind = ctrl+j=ignore\nforeground = #eeeeee\n")
        XCTAssertEqual(TerminalConfigurationSync.entries(of: settings), ["foreground": ["#eeeeee"], "keybind": ["clear", "ctrl+j=ignore"]])
        XCTAssertTrue(try TerminalConfigurationSync.changes(from: XCTUnwrap(TerminalConfigurationSync.entries(of: settings)), to: remote).isEmpty)
    }

    /// A file that cannot be read says nothing about the settings that
    /// travel: none are read from it, and another device's do not replace it.
    @MainActor func testAnUnreadableFileNeitherSyncsNorIsReplaced() throws {
        let malformed = try scratchSettings("background = #111111\nthis line has no equals sign\n")
        XCTAssertNil(TerminalConfigurationSync.entries(of: malformed))
        TerminalConfigurationSync.adopt(["foreground": ["#eeeeee"]], into: malformed)
        XCTAssertEqual(malformed.applied.text, "background = #111111\nthis line has no equals sign\n")

        let url = FileManager.default.temporaryDirectory.appending(path: "RayonTerminalTests-\(UUID())/config.ghostty")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let bytes = Data("background = #111111\n".utf8) + Data([0xFF, 0xFE, 0x0A])
        try bytes.write(to: url)
        let binary = TerminalSettings(fileURL: url, defaults: .standard)
        XCTAssertNil(TerminalConfigurationSync.entries(of: binary))
        XCTAssertNotNil(binary.issue)
        TerminalConfigurationSync.adopt(["foreground": ["#eeeeee"]], into: binary)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    /// A listener to a change that changes the settings again (iCloud sync
    /// applying another device's) builds on that change, not on what was
    /// there before it.
    @MainActor func testAListenerBuildsOnTheChangeItHears() throws {
        let settings = try scratchSettings("font-size = 18\n")
        var adopted = false
        let observer = NotificationCenter.default.addObserver(forName: TerminalSettings.didChange, object: settings, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard !adopted else { return }
                adopted = true
                settings.adopt(["background": ["#202020"]])
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        try settings.load("font-size = 20\n")
        XCTAssertTrue(adopted)
        XCTAssertEqual(settings.applied.text, "font-size = 20\nbackground = #202020\n")
        XCTAssertEqual(settings.config, settings.applied)
    }

    /// Undo does not reach past settings that came from elsewhere (another
    /// device, a restored backup): it would put back what they replaced.
    @MainActor func testUndoStopsAtAdoptedAndLoadedSettings() throws {
        let settings = try scratchSettings("background = #111111\n")
        settings.set("background", "#222222")
        XCTAssertTrue(settings.applyNow())
        XCTAssertTrue(settings.undoManager.canUndo)
        settings.adopt(["background": ["#333333"]])
        XCTAssertFalse(settings.undoManager.canUndo)
        settings.undo()
        XCTAssertEqual(settings.applied.text, "background = #333333\n")

        settings.set("background", "#444444")
        XCTAssertTrue(settings.applyNow())
        XCTAssertTrue(settings.undoManager.canUndo)
        try settings.load("background = #555555\n")
        XCTAssertFalse(settings.undoManager.canUndo)
    }

    /// The file edited outside Rayon while it runs: a change made in
    /// Settings, or one from another device, is made to the edited file
    /// instead of writing the old one over it.
    @MainActor func testOutsideEditsAreNotOverwritten() throws {
        let settings = try scratchSettings("background = #111111\n")
        func editOutside(_ text: String, at seconds: TimeInterval) throws {
            try Data(text.utf8).write(to: settings.fileURL)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: seconds)], ofItemAtPath: settings.fileURL.path)
        }

        try editOutside("background = #111111\nforeground = #eeeeee\n", at: 10)
        settings.set("cursor-color", "#ff0000")
        XCTAssertTrue(settings.applyNow())
        XCTAssertEqual(try String(contentsOf: settings.fileURL, encoding: .utf8), "background = #111111\nforeground = #eeeeee\ncursor-color = #ff0000\n")

        try editOutside("background = #222222\nforeground = #eeeeee\ncursor-color = #ff0000\n", at: 20)
        XCTAssertEqual(TerminalConfigurationSync.entries(of: settings)?["background"], ["#222222"])
        TerminalConfigurationSync.adopt(["background": ["#222222"], "foreground": ["#dddddd"], "cursor-color": ["#ff0000"]], into: settings)
        XCTAssertEqual(try String(contentsOf: settings.fileURL, encoding: .utf8), "background = #222222\nforeground = #dddddd\ncursor-color = #ff0000\n")
    }
}
