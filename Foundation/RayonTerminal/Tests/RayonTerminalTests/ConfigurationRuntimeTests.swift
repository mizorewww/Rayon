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

    /// Settings of their own, from `text` as an earlier release's
    /// config.ghostty, and a clean shared terminal configuration afterwards.
    @MainActor private func scratchSettings(_ text: String? = nil) throws -> TerminalSettings {
        let folder = FileManager.default.temporaryDirectory.appending(path: "RayonTerminalTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let configFile = folder.appending(path: "config.ghostty")
        if let text { try Data(text.utf8).write(to: configFile) }
        addTeardownBlock { @MainActor in
            try? FileManager.default.removeItem(at: folder)
            try? RayonTerminalConfiguration.apply(TerminalSettings.shared.applied)
        }
        return TerminalSettings(fileURL: folder.appending(path: "terminal-settings.json"), importing: configFile)
    }

    @MainActor func testExplicitGhosttyDefaultOverridesRayonDefault() throws {
        let size = try XCTUnwrap(SettingCatalog.shared.setting("font-size")?.defaultValue.values.first)
        let text = RayonTerminalConfiguration.contents(["font-size": [size], "font-thicken": ["false"]], dark: true)
        XCTAssertTrue(text.contains("font-size = \(size)"))
        let lines = text.components(separatedBy: "\n")
        XCTAssertGreaterThan(try XCTUnwrap(lines.lastIndex(of: "font-thicken = false")), try XCTUnwrap(lines.lastIndex(of: "font-thicken = true")))
    }

    @MainActor func testRuntimeFilterAndDualThemes() throws {
        TestHost.prepare()
        let config = [
            "theme": ["light:3024 Day,dark:3024 Night"], "background": ["#223344"], "command": ["rm -rf /"], "config-file": ["/tmp/config"],
            "clipboard-write": ["deny"], "keybind": ["global:ctrl+k=quit", "ctrl+k=text:hello"],
        ]
        let text = RayonTerminalConfiguration.contents(config, dark: true)
        XCTAssertFalse(text.contains("command ="))
        XCTAssertFalse(text.contains("config-file ="))
        // A user's clipboard-write is filtered out: the only such line is the
        // one the app's sharing preference appends.
        XCTAssertFalse(text.contains("clipboard-write = deny"))
        XCTAssertFalse(text.contains("=quit"))
        XCTAssertTrue(text.contains("ctrl+k=text:hello"))
        XCTAssertTrue(text.contains("background = #090300"))
        XCTAssertTrue(RayonTerminalConfiguration.contents(config, dark: false).contains("background = #f7f7f7"))
        let controller = TerminalController(configuration: RayonTerminalConfiguration.base)
        try RayonTerminalConfiguration.apply(config, to: controller)
        let before = controller.theme
        var broken = config
        broken["font-size"] = ["not a number"]
        XCTAssertThrowsError(try RayonTerminalConfiguration.apply(broken, to: controller))
        XCTAssertEqual(controller.theme, before)
    }

    /// A font feature Ghostty cannot read is refused when typed in Settings;
    /// one already applied is left for Ghostty to skip and keeps neither
    /// the rest nor later changes from applying.
    @MainActor func testAnUnreadableFontFeatureIsRefusedOnlyInSettings() throws {
        let settings = try scratchSettings("font-feature = !!=bad value\nbackground = #111111\n")
        try RayonTerminalConfiguration.apply(settings.applied)
        settings.set("background", "#222222")
        XCTAssertTrue(settings.applyNow(), settings.issue ?? "")
        settings.set("font-feature", ["!!=bad value", "ligatures"])
        XCTAssertFalse(settings.applyNow())
        XCTAssertTrue(settings.issue?.contains("ligatures") == true, settings.issue ?? "")
        settings.set("font-feature", ["!!=bad value", "-liga"])
        XCTAssertTrue(settings.applyNow(), settings.issue ?? "")
    }

    /// The shortcut list as written replaces Ghostty's: a default deleted in
    /// Settings stays deleted.
    @MainActor func testDeletedDefaultShortcutIsUnbound() throws {
        let settings = try scratchSettings()
        let defaults = settings.shortcuts
        XCTAssertFalse(defaults.isEmpty)
        XCTAssertFalse(settings.config["keybind", default: []].contains("clear"))
        settings.setShortcuts(Array(defaults.dropFirst()) + ["ctrl+k=text:hello"])
        XCTAssertEqual(settings.shortcuts, Array(defaults.dropFirst()) + ["ctrl+k=text:hello"])
        XCTAssertEqual(settings.config["keybind"]?.first, "clear")
        let text = RayonTerminalConfiguration.contents(settings.config, dark: true)
        XCTAssertTrue(text.contains("keybind = clear"))
        try RayonTerminalConfiguration.apply(settings.config, to: TerminalController(configuration: .default))
    }

    @MainActor func testFindBarKeysAreNotGhosttys() throws {
        for config in [[:], ["keybind": ["ctrl+k=ignore"]]] {
            let text = RayonTerminalConfiguration.contents(config, dark: false)
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
        try RayonTerminalConfiguration.apply(["font-size": ["13.5"], "theme": ["3024 Night"]])
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
        let settings = try scratchSettings()
        func saved() -> [String: [String]] {
            TerminalSettings(fileURL: settings.fileURL, importing: nil).applied
        }
        settings.set("background", "#123456")
        XCTAssertTrue(settings.applyNow())
        let saved1 = saved()
        XCTAssertEqual(saved1, ["background": ["#123456"]])
        settings.undoManager.undo()
        XCTAssertFalse(settings.isSet("background"))
        settings.undoManager.redo()
        XCTAssertEqual(settings.value("background"), "#123456")
        XCTAssertTrue(settings.applyNow())
        // A value Ghostty rejects is shown but neither applied nor saved.
        settings.set("font-size", "not a number")
        XCTAssertFalse(settings.applyNow())
        XCTAssertNotNil(settings.issue)
        XCTAssertNil(settings.applied["font-size"])
        let saved2 = saved()
        XCTAssertNil(saved2["font-size"])
        settings.resetAll()
        XCTAssertTrue(settings.applyNow())
        XCTAssertNil(settings.issue)
        let saved3 = saved()
        XCTAssertEqual(saved3, [:])
    }

    /// A change still waiting out its pause is saved when the app quits,
    /// and one that cannot be saved is neither applied nor announced.
    @MainActor func testFlushSavesAndAFailedSaveAppliesNothing() throws {
        let settings = try scratchSettings()
        settings.set("background", "#123456")
        settings.flush()
        XCTAssertEqual(TerminalSettings(fileURL: settings.fileURL, importing: nil).applied, ["background": ["#123456"]])

        let blocker = FileManager.default.temporaryDirectory.appending(path: "RayonTerminalTests-\(UUID())")
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let unsaved = TerminalSettings(fileURL: blocker.appending(path: "terminal-settings.json"), importing: nil)
        var announced = false
        let observer = NotificationCenter.default.addObserver(forName: TerminalSettings.didChange, object: unsaved, queue: .main) { _ in
            MainActor.assumeIsolated { announced = true }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        unsaved.set("background", "#654321")
        XCTAssertFalse(unsaved.applyNow())
        XCTAssertNotNil(unsaved.issue)
        XCTAssertEqual(unsaved.applied, [:])
        XCTAssertFalse(announced)
    }

    @MainActor func testPaletteAndEffectiveColors() throws {
        let settings = try scratchSettings("theme = light:3024 Day,dark:3024 Night\n")
        XCTAssertEqual(settings.effectiveColor("background", dark: false), "#f7f7f7")
        XCTAssertEqual(settings.effectiveColor("background", dark: true), "#090300")
        settings.set("background", "#123456")
        XCTAssertEqual(settings.effectiveColor("background", dark: true), "#123456")
        settings.setPalette(255, "#010203")
        settings.setPalette(2, "#112233")
        XCTAssertEqual(settings.config["palette"], ["2=#112233", "255=#010203"])
        XCTAssertEqual(settings.effectivePalette(255, dark: true), "#010203")
        settings.setPalette(255, nil)
        settings.setPalette(2, nil)
        XCTAssertFalse(settings.isSet("palette"))
    }

    /// An earlier release's config.ghostty moves into the settings at the
    /// first launch, without comments, malformed lines or options Rayon's
    /// terminal does not use, which are reported; the file is kept as
    /// config.ghostty.imported, and its time stays the settings' time, for
    /// sync.
    @MainActor func testConfigGhosttyIsImportedOnce() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "RayonTerminalTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let configFile = folder.appending(path: "config.ghostty")
        let text = "# mine\r\nfont-size = 15\nfont-family = \"Menlo\"\nfont-family = SF Mono\nmacos-titlebar-style = tabs\nbroken line\nkeybind = clear\nkeybind = ctrl+k=ignore\npalette = 1=#010101\nbackground =\n"
        try Data(text.utf8).write(to: configFile)
        let written = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: configFile.path)
        let url = folder.appending(path: "terminal-settings.json")

        let settings = TerminalSettings(fileURL: url, importing: configFile)
        let expected = ["font-size": ["15"], "font-family": ["Menlo", "SF Mono"], "keybind": ["clear", "ctrl+k=ignore"], "palette": ["1=#010101"]]
        XCTAssertEqual(settings.applied, expected)
        XCTAssertEqual(settings.shortcuts, ["ctrl+k=ignore"])
        XCTAssertEqual(settings.paletteOverrides, [1: "#010101"])
        XCTAssertEqual(settings.modified, written)
        XCTAssertFalse(FileManager.default.fileExists(atPath: configFile.path))
        XCTAssertEqual(try Data(contentsOf: configFile.appendingPathExtension("imported")), Data(text.utf8))
        XCTAssertEqual(settings.lastImport?.earlierRelease, true)
        XCTAssertEqual(settings.lastImport?.skipped, ["macos-titlebar-style"])

        // A config.ghostty that turns up later is not read.
        try Data("font-size = 30\n".utf8).write(to: configFile)
        let relaunched = TerminalSettings(fileURL: url, importing: configFile)
        XCTAssertEqual(relaunched.applied, expected)
        XCTAssertEqual(relaunched.modified, written)
        XCTAssertNil(relaunched.lastImport)
    }

    /// What another device set is applied at once and is not something
    /// Undo takes back.
    @MainActor func testAdoptingRemoteChanges() throws {
        let settings = try scratchSettings("font-size = 16\n")
        settings.adopt(["background": ["#222222"], "font-size": nil])
        XCTAssertEqual(settings.applied, ["background": ["#222222"]])
        XCTAssertFalse(settings.undoManager.canUndo)
        settings.adopt(["font-size": ["not a number"]])
        XCTAssertNotNil(settings.issue)
        XCTAssertNil(settings.applied["font-size"])
    }

    /// What syncs leaves the device's own keys alone, both ways.
    @MainActor func testSyncCarriesAllButDeviceBoundKeys() throws {
        let settings = try scratchSettings("font-size = 16\nwindow-padding-x = 4\nbackground = #111111\nkeybind = clear\nkeybind = ctrl+k=ignore\n")
        XCTAssertEqual(TerminalConfigurationSync.entries(of: settings), [
            "background": ["#111111"], "keybind": ["clear", "ctrl+k=ignore"],
        ])
        let remote = ["foreground": ["#eeeeee"], "keybind": ["clear", "ctrl+j=ignore"], "font-size": ["30"], "window-padding-y": ["9"]]
        let expected: [String: [String]?] = [
            "background": nil as [String]?, "foreground": ["#eeeeee"], "keybind": ["clear", "ctrl+j=ignore"],
        ]
        XCTAssertEqual(TerminalConfigurationSync.changes(from: TerminalConfigurationSync.entries(of: settings), to: remote), expected)
        TerminalConfigurationSync.adopt(remote, into: settings)
        XCTAssertEqual(settings.applied, ["font-size": ["16"], "window-padding-x": ["4"], "keybind": ["clear", "ctrl+j=ignore"], "foreground": ["#eeeeee"]])
        XCTAssertEqual(TerminalConfigurationSync.entries(of: settings), ["foreground": ["#eeeeee"], "keybind": ["clear", "ctrl+j=ignore"]])
        XCTAssertTrue(TerminalConfigurationSync.changes(from: TerminalConfigurationSync.entries(of: settings), to: remote).isEmpty)
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
        try settings.load(["font-size": ["20"]])
        XCTAssertTrue(adopted)
        XCTAssertEqual(settings.applied, ["font-size": ["20"], "background": ["#202020"]])
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
        XCTAssertEqual(settings.applied, ["background": ["#333333"]])

        settings.set("background", "#444444")
        XCTAssertTrue(settings.applyNow())
        XCTAssertTrue(settings.undoManager.canUndo)
        try settings.load(ghosttyConfig: "background = #555555\n")
        XCTAssertFalse(settings.undoManager.canUndo)
        XCTAssertEqual(settings.applied, ["background": ["#555555"]])
    }
}
