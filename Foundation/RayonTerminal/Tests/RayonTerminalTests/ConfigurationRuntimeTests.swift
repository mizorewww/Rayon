import AppKit
import GhosttyTerminal
import XCTest
@testable import RayonTerminal

final class ConfigurationRuntimeTests: XCTestCase {
    func testKeybindingGrammarAndArguments() {
        XCTAssertTrue(ConfigKeybinding("ctrl++=text:a=b:c").errors.isEmpty)
        XCTAssertTrue(ConfigKeybinding("+=ignore").errors.isEmpty)
        XCTAssertEqual(ConfigKeybinding("ctrl++=text:a=b:c").argument, "a=b:c")
        XCTAssertEqual(ConfigKeybinding("unconsumed:cmd+ctrl+k=ignore").canonical,
                       ConfigKeybinding("control+super+k=ignore").canonical)
        XCTAssertTrue(ConfigKeybinding("super+ArrowUp=scroll_to_top").errors.isEmpty)
        XCTAssertFalse(ConfigKeybinding("global:super+k>c=ignore").errors.isEmpty)
        XCTAssertFalse(ConfigKeybinding("ctrl+k=goto_tab:0").errors.isEmpty)
        XCTAssertFalse(ConfigKeybinding("ctrl+k=resize_split:sideways,-1").errors.isEmpty)
        XCTAssertEqual(ConfigKeybindingCatalog.shared.actions.count, 83)
    }
    @MainActor func testSandboxIsolationChainsHistoryAndCompletion() throws {
        let shell = ConfigSandbox()
        shell.input = "mkdir Demo && cd Demo && touch hello && ls"
        shell.submit()
        XCTAssertEqual(shell.cwd, "/Demo")
        XCTAssertNotNil(shell.files["/Demo/hello"])
        XCTAssertEqual(shell.lines.last?.text, "hello")
        shell.input = "cat missing && echo should-not-run"; shell.submit()
        XCTAssertFalse(shell.lines.last?.text.contains("should-not-run") == true)
        shell.input = "echo '中文 && x'"; shell.submit()
        XCTAssertEqual(shell.lines.last?.text, "中文 && x")
        shell.historyMove(-1); XCTAssertEqual(shell.input, "echo '中文 && x'")
        shell.input = "pw"; shell.complete(); XCTAssertEqual(shell.input, "pwd")
        XCTAssertThrowsError(try ConfigSandbox.tokenize("echo 'unfinished"))
        XCTAssertEqual(shell.path("../../Documents"), "/Documents")
    }
    @MainActor func testExplicitGhosttyDefaultCanOverrideRayonLegacyDefault() {
        var doc = ConfigDocument()
        let size = ConfigCatalog.shared.registry["fontSize"]!.defaultValue.text
        let thicken = ConfigCatalog.shared.registry["fontThicken"]!.defaultValue.text
        doc.set("font-size", [size]); doc.set("font-thicken", [thicken])
        XCTAssertEqual(doc.overrides["font-size"], [size])
        XCTAssertFalse(doc.serialized().contains("font-size ="))
        let runtime = RayonTerminalConfiguration.runtimeContents(doc, dark: true)
        XCTAssertTrue(runtime.contains("font-size = \(size)"))
        XCTAssertTrue(runtime.contains("font-thicken = \(thicken)"))
    }
    @MainActor func testRuntimeFilterAndDualThemes() throws {
        _ = NSApplication.shared
        var doc = ConfigDocument()
        try doc.merge("theme = light:3024 Day,dark:3024 Night\nbackground = #223344\ncommand = rm -rf /\nconfig-file = /tmp/config\nclipboard-write = allow\nkeybind = global:ctrl+k=quit\nkeybind = ctrl+k=text:hello")
        let text = RayonTerminalConfiguration.runtimeContents(doc, dark: true)
        XCTAssertFalse(text.contains("command ="))
        XCTAssertFalse(text.contains("config-file ="))
        XCTAssertFalse(text.contains("= allow"))
        XCTAssertFalse(text.contains("=quit"))
        XCTAssertTrue(text.contains("ctrl+k=text:hello"))
        let controller = TerminalController(configuration: .default)
        try RayonTerminalConfiguration.apply(doc, to: controller)
        XCTAssertTrue(controller.renderedConfig.contains("background = #223344"))
        let before = controller.renderedConfig
        doc.set("font-size", ["not a number"])
        XCTAssertThrowsError(try RayonTerminalConfiguration.apply(doc, to: controller))
        XCTAssertEqual(controller.renderedConfig, before)
    }
    func testCompoundDurationValidation() throws {
        XCTAssertEqual(ConfigDuration.humanize(try ConfigDuration.parse("1h30m", allowEmpty: false)), "1 hour, 30 minutes")
        XCTAssertEqual(try ConfigDuration.parse("4ms", allowEmpty: false).first?.1, "ms")
        XCTAssertThrowsError(try ConfigDuration.parse("1s2s", allowEmpty: false))
        XCTAssertThrowsError(try ConfigDuration.parse("-1m", allowEmpty: false))
        XCTAssertThrowsError(try ConfigDuration.parse("1.5s", allowEmpty: false))
        XCTAssertTrue(try ConfigDuration.parse("", allowEmpty: true).isEmpty)
    }
    func testScrollMultiplierLabelsAndDefaults() {
        XCTAssertEqual(ConfigPairCodec.parse("discrete:3,precision:1", scroll: true).values, ["1", "3"])
        XCTAssertEqual(ConfigPairCodec.parse("precision:2", scroll: true).values, ["2", "3"])
        XCTAssertFalse(ConfigPairCodec.parse("precision:2", scroll: true).linked)
        XCTAssertEqual(ConfigPairCodec.parse("", scroll: true).values, ["1", "3"])
        XCTAssertTrue(ConfigPairCodec.parse("2", scroll: true).linked)
    }
    @MainActor func testApplyPreservesSurfaceAndFractionalFontForNewSessions() async throws {
        _ = NSApplication.shared
        defer { try? RayonTerminalConfiguration.apply(ConfigEditorModel.storedDocument()) }
        let terminal = RayonTerminalView()
        let native = terminal.session.platformView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = native; window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        terminal.write("configuration survival marker\r\n")
        XCTAssertTrue(terminal.session.backend.waitForPendingOutput())
        var document = ConfigDocument()
        document.set("font-size", ["13.5"])
        document.set("theme", ["3024 Night"])
        try RayonTerminalConfiguration.apply(document)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(native === terminal.session.platformView())
        XCTAssertEqual(native.fontSize, 13.5)
        XCTAssertTrue(terminal.session.backend.readViewportText()?.contains("configuration survival marker") == true)
        terminal.setTerminalFontSize(with: 14, preferConfigured: true)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(native.fontSize, 13.5)
        // A fresh batch/interactive view shares the same exact (non-rounded) configuration.
        let next = RayonTerminalView()
        let second = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        second.isReleasedWhenClosed = false; second.contentView = next.session.platformView(); second.orderFront(nil)
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
    @MainActor func testDraftPersistenceUndoAndFailedImport() throws {
        let suite = "RayonConfigurationTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ConfigEditorModel(defaults: defaults)
        model.edit { $0.set("background", ["#123456"]) }
        XCTAssertTrue(model.isDirty)
        model.undo(); XCTAssertFalse(model.isDirty)
        model.redo(); XCTAssertEqual(model.document.text("background"), "#123456")
        model.edit {
            var bindings = $0.values("keybind"); bindings.removeFirst(); bindings.append("ctrl+k=text:custom")
            $0.set("keybind", bindings)
            $0.overrides["font-family"] = []
            $0.setPalette(1, color: ConfigCatalog.shared.registry["palette"]!.defaultValue.values[1])
        }
        let before = model.document
        XCTAssertThrowsError(try model.importConfig("palette = broken"))
        XCTAssertEqual(model.document, before)
        XCTAssertTrue(model.save())
        XCTAssertEqual(ConfigEditorModel(defaults: defaults).document, before)
        // The shared controller was temporarily changed by Save; restore its persisted production state.
        try RayonTerminalConfiguration.apply(ConfigEditorModel.storedDocument())
    }
}
