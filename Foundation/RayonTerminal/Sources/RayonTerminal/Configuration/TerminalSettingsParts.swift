import SwiftUI

// The terminal's settings as parts an app arranges in its own Settings: the
// categories to list, a category's page, search, the tools and what goes
// around them. `GhosttyConfigurationView` is the same parts on their own.

/// A category of terminal settings (Text, Colors, …).
public struct TerminalSettingsCategory: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let icon: String

    /// Every terminal category, in the order Settings lists them.
    public static let all: [TerminalSettingsCategory] = SettingsLayout.categories
        .map { TerminalSettingsCategory(id: $0.id, title: $0.title, icon: $0.icon) }

    var layout: SettingsLayout.Category? {
        SettingsLayout.category(id)
    }

    /// Whether its page shows the live terminal preview.
    public var previews: Bool {
        layout?.previews ?? false
    }

    /// How many of its settings are set.
    @MainActor public var changedCount: Int {
        TerminalSettings.shared.changedCounts[id] ?? 0
    }
}

/// One category's settings as a form; `header` comes first, for the app's
/// own rows. `terminalPreview(isShown:)` around it adds the preview.
public struct TerminalSettingsPage<Header: View>: View {
    private let category: TerminalSettingsCategory
    private let header: Header

    public init(_ category: TerminalSettingsCategory, @ViewBuilder header: () -> Header) {
        self.category = category
        self.header = header()
    }

    public var body: some View {
        if let layout = category.layout {
            CategoryPage(category: layout, header: AnyView(header))
        }
    }
}

public extension TerminalSettingsPage where Header == EmptyView {
    init(_ category: TerminalSettingsCategory) {
        self.init(category) { EmptyView() }
    }
}

/// The terminal settings matching every word of a query, worked out once.
public struct TerminalSettingsSearch {
    let query: String
    let results: [SearchResults.Match]

    @MainActor public init(_ query: String) {
        self.query = query
        results = SearchResults.results(for: query, in: SettingsLayout.categories)
    }

    /// Whether no terminal setting matches.
    public var isEmpty: Bool {
        results.isEmpty
    }
}

/// A search's terminal settings as form sections under their categories;
/// `show` opens a category.
public struct TerminalSettingsSearchSections: View {
    private let search: SearchResults

    public init(_ search: TerminalSettingsSearch, show: @escaping (String) -> Void) {
        self.search = SearchResults(query: search.query, results: search.results, show: show)
    }

    public var body: some View {
        search.sections(search.results)
    }
}

/// Undo, Redo, the preview, Import from Ghostty and Reset.
public struct TerminalSettingsTools: View {
    @Binding private var showsPreview: Bool
    @Binding private var confirmingReset: Bool
    private let previewAvailable: Bool
    private let resetAvailable: Bool
    private var settings: TerminalSettings {
        .shared
    }

    public init(showsPreview: Binding<Bool>, confirmingReset: Binding<Bool>, previewAvailable: Bool, resetAvailable: Bool) {
        _showsPreview = showsPreview
        _confirmingReset = confirmingReset
        self.previewAvailable = previewAvailable
        self.resetAvailable = resetAvailable
    }

    public var body: some View {
        let _ = settings.revision
        Button { settings.undo() } label: { Label(.init("Undo", bundle: .module), systemImage: "arrow.uturn.backward") }
            .disabled(!settings.undoManager.canUndo)
            .help(.init("Undo the last terminal setting change", bundle: .module))
        Button { settings.redo() } label: { Label(.init("Redo", bundle: .module), systemImage: "arrow.uturn.forward") }
            .disabled(!settings.undoManager.canRedo)
            .help(.init("Redo", bundle: .module))
        Toggle(isOn: $showsPreview.animation()) { Label(.init("Preview", bundle: .module), systemImage: "rectangle.topthird.inset.filled") }
            .disabled(!previewAvailable)
            .help(showsPreview ? String(localized: "Hide the terminal preview", bundle: .module) : String(localized: "Show a terminal preview above the settings", bundle: .module))
        #if os(macOS)
            Button { settings.importFromGhostty() } label: {
                Label(.init("Import from Ghostty…", bundle: .module), systemImage: "square.and.arrow.down")
            }
            .help(.init("Take the settings Rayon's terminal uses from Ghostty's configuration", bundle: .module))
        #endif
        Button(role: .destructive) { confirmingReset = true } label: {
            Label(.init("Reset Terminal Settings…", bundle: .module), systemImage: "arrow.counterclockwise")
        }
        .disabled(!resetAvailable)
        .help(.init("Reset every terminal setting to its default", bundle: .module))
    }
}

public extension View {
    /// What goes around terminal settings: why the last change was not
    /// applied, what Import from Ghostty did, and the confirmation
    /// `TerminalSettingsTools`' Reset asks for.
    /// The issue floats over the bottom edge: a safe-area inset there would
    /// make the form measure every row, not just the visible ones, on each
    /// change and page switch.
    func terminalSettingsChrome(confirmingReset: Binding<Bool>) -> some View {
        overlay(alignment: .bottom) { IssueBar() }
        #if os(macOS)
            .modifier(GhosttyImportAlert())
        #endif
            .confirmationDialog(Text("Reset every terminal setting to its default?", bundle: .module), isPresented: confirmingReset) {
                Button(.init("Reset", bundle: .module), role: .destructive) { TerminalSettings.shared.resetAll() }
            } message: {
                Text("Only the terminal's settings are reset; Rayon's own are kept.", bundle: .module)
            }
    }
}

#if os(macOS)
    /// What `TerminalSettingsTools`' Import from Ghostty found.
    private struct GhosttyImportAlert: ViewModifier {
        private var settings: TerminalSettings {
            .shared
        }

        func body(content: Content) -> some View {
            let shown = Binding { settings.lastImport != nil } set: { if !$0 { settings.lastImport = nil } }
            let result = settings.lastImport
            content.alert(
                result?.found == false ? Text("No Ghostty configuration found", bundle: .module) : Text("Imported from Ghostty", bundle: .module),
                isPresented: shown,
                presenting: result
            ) { _ in } message: { result in
                if !result.found {
                    Text("Ghostty keeps its configuration in ~/.config/ghostty or ~/Library/Application Support/com.mitchellh.ghostty.", bundle: .module)
                } else if result.skipped.isEmpty {
                    Text("Settings imported: \(result.imported)", bundle: .module)
                } else {
                    Text("Settings imported: \(result.imported). Skipped, as Rayon's terminal does not use them: \(result.skipped.formatted(.list(type: .and)))", bundle: .module)
                }
            }
        }
    }
#endif
