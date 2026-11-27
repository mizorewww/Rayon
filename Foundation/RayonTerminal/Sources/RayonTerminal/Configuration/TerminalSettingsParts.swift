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

    /// How many of its settings are set in config.ghostty.
    @MainActor public var changedCount: Int {
        (layout?.keys ?? []).filter(TerminalSettings.shared.isSet).count
    }
}

/// One category's settings as a form, with the terminal preview above when
/// it helps; `header` comes first, for the app's own rows.
public struct TerminalSettingsPage<Header: View>: View {
    private let category: TerminalSettingsCategory
    @Binding private var showsPreview: Bool
    private let header: Header

    public init(_ category: TerminalSettingsCategory, showsPreview: Binding<Bool>, @ViewBuilder header: () -> Header) {
        self.category = category
        _showsPreview = showsPreview
        self.header = header()
    }

    public var body: some View {
        if let layout = category.layout {
            CategoryPage(category: layout, showsPreview: $showsPreview, header: AnyView(header))
        }
    }
}

public extension TerminalSettingsPage where Header == EmptyView {
    init(_ category: TerminalSettingsCategory, showsPreview: Binding<Bool>) {
        self.init(category, showsPreview: showsPreview) { EmptyView() }
    }
}

/// The terminal settings matching every word of `query`, as form sections
/// under their categories; `show` opens a category.
public struct TerminalSettingsSearchSections: View {
    private let search: SearchResults

    public init(query: String, show: @escaping (String) -> Void) {
        search = SearchResults(
            query: query,
            categories: SettingsLayout.categories,
            show: show
        )
    }

    /// Whether any terminal setting matches `query`.
    @MainActor public static func matches(_ query: String) -> Bool {
        !TerminalSettingsSearchSections(query: query) { _ in }.search.results.isEmpty
    }

    public var body: some View {
        search.sections(search.results)
    }
}

/// Undo, Redo, the preview, the file and Reset.
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
        Button(role: .destructive) { confirmingReset = true } label: {
            Label(.init("Reset Terminal Settings…", bundle: .module), systemImage: "arrow.counterclockwise")
        }
        .disabled(!resetAvailable)
        .help(.init("Reset every terminal setting to its default", bundle: .module))
    }
}

public extension View {
    /// What goes around terminal settings: why the last change was not
    /// applied, and the confirmation `TerminalSettingsTools`' Reset asks for.
    func terminalSettingsChrome(confirmingReset: Binding<Bool>) -> some View {
        safeAreaInset(edge: .bottom) { IssueBar() }
            .confirmationDialog(Text("Reset every terminal setting to its default?", bundle: .module), isPresented: confirmingReset) {
                Button(.init("Reset", bundle: .module), role: .destructive) { TerminalSettings.shared.resetAll() }
            } message: {
                Text("Only the terminal's settings are reset; Rayon's own are kept.", bundle: .module)
            }
    }
}
