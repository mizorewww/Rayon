import AppKit
import SwiftUI
import GhosttyTerminal

@MainActor
final class ConfigEditorModel: ObservableObject {
    static let shared = ConfigEditorModel()
    @Published private(set) var document: ConfigDocument
    @Published private(set) var saved: ConfigDocument
    @Published var message = ""
    @Published private(set) var undoStack: [ConfigDocument] = []
    @Published private(set) var redoStack: [ConfigDocument] = []
    /// Called after a change is applied, with the new font size when it changed.
    var onApplied: ((Double?) -> Void)?
    private var pendingSave: Task<Void, Never>?
    private let defaults: UserDefaults
    private struct Storage: Codable { let version: Int; let document: ConfigDocument }
    private static let snapshotKey = "wiki.qaq.rayon.ghosttyConfiguration.v1"
    private static let storageKey = "wiki.qaq.rayon.ghosttyConfiguration"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var document = ConfigDocument()
        var issue = ""
        do {
            if let data = defaults.data(forKey: Self.snapshotKey) {
                let storage = try JSONDecoder().decode(Storage.self, from: data)
                guard storage.version == 1 else { throw ConfigError.message("Unsupported configuration storage version") }
                document = storage.document
            } else if let source = defaults.string(forKey: Self.storageKey) { try document.merge(source) }
        } catch { issue = "Saved configuration could not be read: \(error.localizedDescription). The original is retained until you explicitly save." }
        self.document = document
        saved = document
        message = issue
    }
    var isDirty: Bool { document != saved }
    func edit(_ mutation: (inout ConfigDocument) -> Void) {
        var next = document
        mutation(&next)
        guard next != document else { return }
        undoStack.append(document)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
        document = next
        scheduleSave()
    }
    func binding(_ key: String) -> Binding<String> {
        Binding(get: { self.document.text(key) }, set: { value in self.edit { $0.set(key, [value]) } })
    }
    func undo() { guard let previous = undoStack.popLast() else { return }; redoStack.append(document); document = previous; scheduleSave() }
    func redo() { guard let next = redoStack.popLast() else { return }; undoStack.append(document); document = next; scheduleSave() }

    /// Settings save themselves: a short pause after the last change, then apply.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self, self.isDirty else { return }
            let fontChanged = self.document.overrides["font-size"] != self.saved.overrides["font-size"]
            if self.save(), fontChanged {
                self.onApplied?(self.document.overrides["font-size"]?.first.flatMap(Double.init) ?? 14)
            }
        }
    }
    func reset(_ key: String) { edit { $0.overrides.removeValue(forKey: key) } }
    func importConfig(_ source: String) throws {
        var next = document
        try next.merge(source)
        edit { $0 = next }
    }
    func save() -> Bool {
        do {
            try RayonTerminalConfiguration.apply(document)
            defaults.set(try JSONEncoder().encode(Storage(version: 1, document: document)), forKey: Self.snapshotKey)
            saved = document
            message = ""
            return true
        } catch { message = error.localizedDescription; return false }
    }
    static func storedDocument() -> ConfigDocument { ConfigEditorModel().document }
}

/// Shared by existing and future SSH surfaces. Updating this controller preserves the backend and scrollback.
@MainActor
public enum RayonTerminalConfiguration {
    static let didApply = Notification.Name("RayonTerminalConfigurationDidApply")
    static var appliedFontSize: Double? = ConfigEditorModel.storedDocument().overrides["font-size"]?.first.flatMap(Double.init)
    static let controller: TerminalController = {
        let result = TerminalController(configuration: TerminalConfiguration.default
            .custom("clipboard-read", "ask").custom("clipboard-write", "ask"))
        let document = ConfigEditorModel.storedDocument()
        if !document.overrides.isEmpty { try? apply(document, to: result) }
        return result
    }()

    /// Values Rayon's terminal starts from where they differ from Ghostty's own
    /// defaults (font size 14, thickened text, blinking block cursor). The editor
    /// shows these as the defaults, because they are what the terminal uses.
    nonisolated static let runtimeDefaults: [String: [String]] = {
        var result: [String: [String]] = [:]
        for line in TerminalConfiguration.default.rendered.components(separatedBy: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            result[key, default: []].append(value)
        }
        return result
    }()

    nonisolated static let supportedKeys: Set<String> = [
        "background", "foreground", "background-opacity", "background-blur", "background-opacity-cells",
        "selection-background", "selection-foreground", "selection-clear-on-typing", "selection-clear-on-copy",
        "cursor-color", "cursor-text", "cursor-style", "cursor-style-blink", "cursor-opacity", "cursor-click-to-move",
        "palette", "bold-color", "minimum-contrast", "theme", "keybind", "font-size",
        "font-family", "font-family-bold", "font-family-italic", "font-family-bold-italic", "font-feature",
        "font-variation", "font-variation-bold", "font-variation-italic", "font-variation-bold-italic",
        "font-thicken", "font-thicken-strength", "font-style", "font-style-bold", "font-style-italic", "font-style-bold-italic",
        "font-codepoint-map", "font-synthetic-style", "freetype-load-flags", "grapheme-width-method",
        "adjust-cell-width", "adjust-cell-height", "adjust-font-baseline", "adjust-underline-position", "adjust-underline-thickness",
        "adjust-strikethrough-position", "adjust-strikethrough-thickness", "adjust-cursor-thickness", "adjust-cursor-height",
        "adjust-box-thickness", "adjust-overline-position", "adjust-overline-thickness",
        "mouse-hide-while-typing", "mouse-shift-capture", "mouse-scroll-multiplier", "scrollback-limit",
        "window-padding-x", "window-padding-y", "window-padding-balance", "window-padding-color",
        "copy-on-select", "clipboard-trim-trailing-spaces", "clipboard-paste-protection", "clipboard-paste-bracketed-safe",
        "link-url", "image-storage-limit", "title", "vt-kam-allowed", "enquiry-response"
    ]
    nonisolated static let supportedActions: Set<String> = [
        "ignore", "unbind", "csi", "esc", "text", "cursor_key", "reset", "copy_to_clipboard", "paste_from_clipboard",
        "paste_from_selection", "copy_url_to_clipboard", "copy_title_to_clipboard", "increase_font_size", "decrease_font_size",
        "reset_font_size", "set_font_size", "clear_screen", "select_all", "scroll_to_top", "scroll_to_bottom",
        "scroll_to_selection", "scroll_to_row", "scroll_page_up", "scroll_page_down", "scroll_page_fractional", "scroll_page_lines",
        "adjust_selection", "jump_to_prompt", "toggle_readonly", "toggle_mouse_reporting", "end_key_sequence"
    ]
    static func runtimeContents(_ document: ConfigDocument, dark: Bool) -> String {
        var lines = [TerminalConfiguration.default.rendered]
        if let theme = document.effectiveTheme(dark: dark) {
            lines += theme.entries.map { "\($0.0) = \($0.1)" }
        }
        for key in document.overrides.keys.sorted() where supportedKeys.contains(key) && key != "theme" {
            for value in document.overrides[key] ?? [] {
                if key == "keybind" {
                    let parsed = ConfigKeybinding(value)
                    guard parsed.errors.isEmpty, parsed.prefixes.allSatisfy({ $0 != "global" && $0 != "all" }),
                          supportedActions.contains(parsed.action) else { continue }
                }
                // Values are a single Ghostty line; multiline text is represented by escapes.
                guard !value.contains("\n"), !value.contains("\r") else { continue }
                lines.append("\(key) = \(value)")
            }
        }
        lines += ["clipboard-read = ask", "clipboard-write = ask"]
        return lines.joined(separator: "\n")
    }
    static func apply(_ document: ConfigDocument, to target: TerminalController? = nil) throws {
        for (key, values) in document.overrides where supportedKeys.contains(key) {
            if values.contains(where: { $0.contains("\n") || $0.contains("\r") }) {
                throw ConfigError.message("\(key): use escaped characters instead of literal newlines")
            }
        }
        let isShared = target == nil
        let target = target ?? controller
        // Themes are materialized from the bundled catalog, so all 633 work offline.
        // Two theme variants are generated with explicit overrides last.
        let light = runtimeContents(document, dark: false)
        let dark = runtimeContents(document, dark: true)
        // Validate both variants before changing the live controller.
        for contents in Set([light, dark]) {
            let validation = TerminalController(configSource: .generated(contents), theme: .init())
            if let issue = validation.lastConfigurationIssue { throw ConfigError.message(issue) }
        }
        func configuration(_ text: String) -> TerminalConfiguration {
            text.components(separatedBy: "\n").reduce(TerminalConfiguration()) { result, line in
                guard let eq = line.firstIndex(of: "=") else { return result }
                return result.custom(String(line[..<eq]).trimmingCharacters(in: .whitespaces),
                                     String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces))
            }
        }
        let theme = TerminalTheme(light: configuration(light), dark: configuration(dark))
        if target.theme != theme, !target.setTheme(theme) {
            throw ConfigError.message(target.lastConfigurationIssue ?? "Unable to apply configuration")
        }
        if isShared {
            appliedFontSize = document.overrides["font-size"]?.first.flatMap(Double.init)
            NotificationCenter.default.post(name: didApply, object: nil)
        }
    }
}
