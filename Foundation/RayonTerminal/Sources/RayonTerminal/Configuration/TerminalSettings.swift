import Foundation
import Observation

/// The terminal's settings: each Ghostty option set, with its values, kept
/// as JSON in the app's Application Support folder. A change is applied to
/// every open terminal a moment later, once Ghostty accepts it, and only
/// then saved. Ghostty's config text is made from them in memory.
@MainActor @Observable
public final class TerminalSettings {
    public static let shared = TerminalSettings()

    /// Posted after a change was applied and saved.
    public static let didChange = Notification.Name("me.mizorewww.rayon.terminalSettings.didChange")

    public let fileURL: URL

    /// What Settings shows, including a change not applied yet.
    private(set) var config: [String: [String]] {
        didSet {
            if Set(config.keys) != Set(oldValue.keys) { countChanges() }
        }
    }

    /// How many of each category's settings are set, by category: what the
    /// sidebar's badges read, so a change redraws them only when a count
    /// changes rather than on every slider step.
    private(set) var changedCounts: [String: Int] = [:]
    /// What the terminals use and is saved.
    public private(set) var applied: [String: [String]]
    /// When the applied settings last changed, here or from elsewhere; nil
    /// before they ever did.
    @ObservationIgnored public private(set) var modified: Date?
    /// Why the last change, or the settings at launch, were not applied.
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
    /// The last save, which the next one waits for so they land in order.
    @ObservationIgnored private var saving: Task<Void, Never>?

    private static var folder: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName, directoryHint: .isDirectory)
    }

    public static var defaultFileURL: URL { folder.appending(path: "terminal-settings.json") }

    /// Where releases before 2026.12 kept the settings, as Ghostty config text.
    public static var configFileURL: URL { folder.appending(path: "config.ghostty") }

    /// Reads the settings at `fileURL`. Before there are any, the settings in
    /// `importing` (an earlier release's config.ghostty) move there, and
    /// that file goes.
    public init(fileURL: URL = defaultFileURL, importing configFile: URL? = configFileURL) {
        self.fileURL = fileURL
        var initial: [String: [String]] = [:]
        if let data = try? Data(contentsOf: fileURL), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            initial = stored.values
            modified = stored.modified
        } else if let configFile, let data = try? Data(contentsOf: configFile) {
            initial = GhosttyConfigImport.parse(String(decoding: data, as: UTF8.self)).values
            // The file's time, so sync weighs these settings by when they were made.
            modified = (try? configFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if (try? Self.write(Stored(values: initial, modified: modified ?? Date()), to: fileURL)) != nil {
                try? FileManager.default.removeItem(at: configFile)
            }
        }
        config = initial
        applied = initial
        countChanges()
    }

    private func countChanges() {
        var counts: [String: Int] = [:]
        for category in SettingsLayout.categories {
            counts[category.id] = category.keys.count(where: { config[$0] != nil })
        }
        if counts != changedCounts { changedCounts = counts }
    }

    private struct Stored: Codable {
        var values: [String: [String]]
        var modified: Date
    }

    // MARK: Reading

    /// The values a key has: as set, else the terminal's default.
    func values(_ key: String) -> [String] {
        config[key] ?? Self.defaultValues(key)
    }

    /// The value of a single-valued key (Ghostty takes the last one).
    func value(_ key: String) -> String { values(key).last ?? "" }

    func isSet(_ key: String) -> Bool { config[key] != nil }

    /// Rayon's terminal defaults where they differ from Ghostty's (font size,
    /// thickening, cursor), then Ghostty's own.
    nonisolated static func defaultValues(_ key: String) -> [String] {
        RayonTerminalConfiguration.runtimeDefaults[key] ?? SettingCatalog.shared.setting(key)?.defaultValue.values ?? []
    }

    // MARK: Changing

    /// Sets a key's values; none removes it, so its default applies.
    func set(_ key: String, _ values: [String]) {
        var next = config
        next[key] = values.isEmpty ? nil : values
        replace(with: next)
    }

    func set(_ key: String, _ value: String) {
        set(key, value.isEmpty ? [] : [value])
    }

    func reset(_ key: String) { set(key, []) }

    /// Every setting goes back to its default.
    func resetAll() {
        replace(with: [:])
    }

    private func replace(with next: [String: [String]]) {
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
            try checkNewFontFeatures(config)
            try commit(config)
            return true
        } catch {
            issue = error.localizedDescription
            return false
        }
    }

    /// Ghostty takes any font feature and passes over one it cannot read
    /// without a word, so a feature typed in Settings is checked first. One
    /// already applied (from a backup, Ghostty's config or another device)
    /// is left for Ghostty to skip: it must not keep the rest from applying,
    /// or every later change in Settings from saving.
    private func checkNewFontFeatures(_ next: [String: [String]]) throws {
        let applied = Set(applied["font-feature"] ?? [])
        for value in next["font-feature"] ?? [] where !applied.contains(value) {
            try FontFeatureValue.validate(value)
        }
    }

    /// Validates `next` with Ghostty, applies it to every terminal, then
    /// saves it. Nothing changes when Ghostty rejects it.
    private func commit(_ next: [String: [String]]) throws {
        let oldSize = applied["font-size"]?.last
        try RayonTerminalConfiguration.apply(next)
        applied = next
        modified = Date()
        issue = nil
        save()
        NotificationCenter.default.post(name: Self.didChange, object: self)
        if let size = next["font-size"]?.last, size != oldSize, let points = Double(size) {
            onFontSizeChange?(points)
        }
    }

    /// Writes the applied settings off the main actor, after the save before.
    private func save() {
        let stored = Stored(values: applied, modified: modified ?? Date())
        let url = fileURL
        let previous = saving
        saving = Task.detached(priority: .utility) { [weak self] in
            await previous?.value
            do {
                try Self.write(stored, to: url)
            } catch {
                let message = String(localized: "The terminal settings were not saved: \(error.localizedDescription)", bundle: .module)
                await MainActor.run { self?.issue = message }
            }
        }
    }

    /// Returns once every change applied so far is saved.
    public func saved() async {
        await saving?.value
    }

    private nonisolated static func write(_ stored: Stored, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(stored)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Replaces every setting (a restored backup, say), once Ghostty accepts
    /// them. Keys the catalog does not have are dropped.
    public func load(_ values: [String: [String]]) throws {
        try take(values.filter { SettingCatalog.shared.setting($0.key) != nil && !$0.value.isEmpty })
    }

    /// Replaces every setting with those Ghostty config text sets (a backup
    /// from an earlier release, say).
    public func load(ghosttyConfig text: String) throws {
        try take(GhosttyConfigImport.parse(text).values)
    }

    /// Shows `next` and commits it, in place of any change not applied yet.
    /// What Settings shows is `next` before the change is announced, so a
    /// listener that changes the settings again builds on it. Undo forgets
    /// the changes before: undoing one would put back what `next` replaced,
    /// and sync would send that on.
    private func take(_ next: [String: [String]]) throws {
        pendingApply?.cancel()
        let previous = config
        config = next
        do {
            try commit(next)
        } catch {
            config = previous
            throw error
        }
        undoManager.removeAllActions()
        revision += 1
    }

    /// Changes that came from elsewhere (another device): applied at once,
    /// over what is being edited here, and not undone by Undo.
    func adopt(_ changes: [String: [String]?]) {
        var next = config
        for (key, values) in changes { next[key] = values.flatMap { $0.isEmpty ? nil : $0 } }
        guard next != applied else { return }
        do {
            try take(next)
        } catch {
            issue = error.localizedDescription
        }
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
