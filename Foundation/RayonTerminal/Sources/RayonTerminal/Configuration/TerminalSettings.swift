import Foundation
import Observation

/// The terminal's settings: one `config.ghostty` in the app's Application
/// Support folder. Settings changes it one key at a time, and whatever else
/// is in the file (comments, keys Settings does not show, their order) stays
/// as written. A change is applied to every open terminal a moment later,
/// once Ghostty accepts it, and only then written to the file.
@MainActor @Observable
public final class TerminalSettings {
    public static let shared = TerminalSettings()

    /// Posted after a change was applied and saved.
    public static let didChange = Notification.Name("me.mizorewww.rayon.terminalSettings.didChange")

    public let fileURL: URL

    /// What Settings shows, including a change not applied yet.
    private(set) var config: GhosttyConfigText
    /// What the terminals use and the file holds.
    private(set) var applied: GhosttyConfigText
    /// Why the last change, or the file at launch, was not applied.
    var issue: String?

    /// Undo and redo for Settings' own changes.
    @ObservationIgnored let undoManager: UndoManager = {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }()

    /// Bumped with each change, so a view showing Undo's state redraws.
    private(set) var revision = 0

    /// Told the new size when an applied change sets another font size.
    @ObservationIgnored public var onFontSizeChange: ((Double) -> Void)?
    @ObservationIgnored private var pendingApply: Task<Void, Never>?

    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName, directoryHint: .isDirectory)
            .appending(path: "config.ghostty")
    }

    public init(fileURL: URL = defaultFileURL, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        var text = (try? String(contentsOf: fileURL, encoding: .utf8)).map(GhosttyConfigText.init)
        if text == nil, let legacy = Self.legacySettings(in: defaults) {
            text = legacy
            if (try? Self.write(legacy, to: fileURL)) != nil {
                defaults.removeObject(forKey: Self.legacyKey)
            }
        }
        let initial = text ?? GhosttyConfigText()
        config = initial
        applied = initial
    }

    // MARK: Reading

    /// The values a key has: as set, else the terminal's default.
    func values(_ key: String) -> [String] {
        let own = config.values(key)
        return own.isEmpty ? Self.defaultValues(key) : own
    }

    /// The value of a single-valued key (Ghostty takes the last one).
    func value(_ key: String) -> String { values(key).last ?? "" }

    func isSet(_ key: String) -> Bool { !config.values(key).isEmpty }

    /// Rayon's terminal defaults where they differ from Ghostty's (font size,
    /// thickening, cursor), then Ghostty's own.
    nonisolated static func defaultValues(_ key: String) -> [String] {
        RayonTerminalConfiguration.runtimeDefaults[key] ?? SettingCatalog.shared.setting(key)?.defaultValue.values ?? []
    }

    // MARK: Changing

    /// Sets a key's values; none removes it, so its default applies.
    func set(_ key: String, _ values: [String]) {
        edit { $0.set(key, values) }
    }

    func set(_ key: String, _ value: String) {
        set(key, value.isEmpty ? [] : [value])
    }

    func reset(_ key: String) { set(key, []) }

    /// Every key Settings shows goes back to its default; comments and keys
    /// it does not know stay.
    func resetAll() {
        edit { config in
            for setting in SettingCatalog.shared.settings { config.set(setting.key, []) }
        }
    }

    private func edit(_ change: (inout GhosttyConfigText) -> Void) {
        var next = config
        change(&next)
        replace(with: next)
    }

    private func replace(with next: GhosttyConfigText) {
        guard next != config else { return }
        let previous = config
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { $0.replace(with: previous) }
        undoManager.endUndoGrouping()
        config = next
        revision += 1
        scheduleApply()
    }

    func undo() { if undoManager.canUndo { undoManager.undo() } }
    func redo() { if undoManager.canRedo { undoManager.redo() } }

    /// A short pause after the last change, so dragging a slider does not
    /// reload Ghostty's configuration on every step.
    private func scheduleApply() {
        pendingApply?.cancel()
        pendingApply = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.applyNow()
        }
    }

    /// Applies what Settings shows to every terminal and saves it.
    @discardableResult
    func applyNow() -> Bool {
        pendingApply?.cancel()
        pendingApply = nil
        do {
            try commit(config)
            return true
        } catch {
            issue = error.localizedDescription
            return false
        }
    }

    /// Validates `next` with Ghostty, applies it to every terminal, then
    /// writes it. Nothing changes when Ghostty rejects it.
    private func commit(_ next: GhosttyConfigText) throws {
        let oldSize = applied.values("font-size").last
        try RayonTerminalConfiguration.apply(next)
        try Self.write(next, to: fileURL)
        applied = next
        issue = nil
        NotificationCenter.default.post(name: Self.didChange, object: self)
        if let size = next.values("font-size").last, size != oldSize, let points = Double(size) {
            onFontSizeChange?(points)
        }
    }

    /// Replaces the whole file (a restored backup, say), once Ghostty accepts it.
    public func load(_ text: String) throws {
        let next = GhosttyConfigText(text)
        pendingApply?.cancel()
        try commit(next)
        config = next
        revision += 1
    }

    /// The file's text, as applied.
    public var contents: String { applied.text }

    /// Changes that came from elsewhere (another device): applied at once,
    /// over what is being edited here, and not undone by Undo.
    func adopt(_ changes: [String: [String]?]) {
        var next = config
        for (key, values) in changes { next.set(key, values ?? []) }
        guard next != applied else { return }
        pendingApply?.cancel()
        do {
            try commit(next)
            config = next
            revision += 1
        } catch {
            issue = error.localizedDescription
        }
    }

    private static func write(_ text: GhosttyConfigText, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.text.utf8).write(to: url, options: .atomic)
    }

    // MARK: Before config.ghostty

    private static let legacyKey = "me.mizorewww.rayon.ghosttyConfiguration.v1"

    /// The settings as the previous release kept them in the user defaults,
    /// as a config file. Its shortcut list was the whole list, hence `clear`.
    /// Applies settings kept the old way (a restored backup from that
    /// release) and removes them from the user defaults.
    public func loadLegacy(from defaults: UserDefaults) throws {
        guard let legacy = Self.legacySettings(in: defaults) else { return }
        try load(legacy.text)
        defaults.removeObject(forKey: Self.legacyKey)
    }

    static func legacySettings(in defaults: UserDefaults) -> GhosttyConfigText? {
        struct Storage: Decodable {
            struct Document: Decodable { let overrides: [String: [String]] }
            let document: Document
        }
        guard let data = defaults.data(forKey: legacyKey),
              let storage = try? JSONDecoder().decode(Storage.self, from: data)
        else { return nil }
        var text = GhosttyConfigText()
        for (key, values) in storage.document.overrides.sorted(by: { $0.key < $1.key }) where !values.isEmpty {
            text.set(key, key == "keybind" ? ["clear"] + values : values)
        }
        return text
    }
}

#if DEBUG
    /// For the app's Settings benchmark: an edit as a control would make it.
    @MainActor
    public enum ConfigBenchmark {
        public static func edit(_ key: String, _ value: String?) {
            if let value { TerminalSettings.shared.set(key, value) } else { TerminalSettings.shared.reset(key) }
        }

        public static func value(_ key: String) -> String? {
            TerminalSettings.shared.isSet(key) ? TerminalSettings.shared.value(key) : nil
        }
    }
#endif
