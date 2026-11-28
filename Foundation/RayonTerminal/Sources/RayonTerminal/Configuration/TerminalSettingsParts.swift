import RayonDesign
import SwiftUI

// The terminal's settings as parts an app arranges in its own Settings: the
// categories to list, a category's page, search and what goes around them.

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

    /// The groups that open as pages of their own from its page.
    public var subpages: [TerminalSettingsSubpage] {
        (layout?.groups ?? []).filter(\.isSubpage).map { TerminalSettingsSubpage(category: self, group: $0.id, title: $0.title) }
    }
}

/// A group of a category's settings shown as a page of its own.
public struct TerminalSettingsSubpage: Identifiable, Hashable, Sendable {
    public let category: TerminalSettingsCategory
    let group: String
    public let title: String

    /// `category/group`, what the app's navigation names it by.
    public var id: String {
        "\(category.id)/\(group)"
    }

    public init?(id: String) {
        let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let category = TerminalSettingsCategory.all.first(where: { $0.id == parts[0] }),
              let subpage = category.subpages.first(where: { $0.group == parts[1] })
        else { return nil }
        self = subpage
    }

    init(category: TerminalSettingsCategory, group: String, title: String) {
        self.category = category
        self.group = group
        self.title = title
    }
}

/// One category's settings, or one of its subpages, as a form; `header`
/// comes first, for the app's own rows. On the Mac `open` shows a subpage
/// from its row; on the iPhone and iPad the row is a `NavigationLink` to the
/// subpage as its value. `terminalPreview(isShown:)` around it adds the
/// preview.
public struct TerminalSettingsPage<Header: View>: View {
    private let category: TerminalSettingsCategory
    private let subpage: TerminalSettingsSubpage?
    private let open: (TerminalSettingsSubpage) -> Void
    private let header: Header

    public init(
        _ category: TerminalSettingsCategory,
        subpage: TerminalSettingsSubpage? = nil,
        open: @escaping (TerminalSettingsSubpage) -> Void = { _ in },
        @ViewBuilder header: () -> Header
    ) {
        self.category = category
        self.subpage = subpage
        self.open = open
        self.header = header()
    }

    public var body: some View {
        if let layout = category.layout {
            CategoryPage(category: layout, subpage: subpage?.group, header: AnyView(header), open: open)
        }
    }
}

public extension TerminalSettingsPage where Header == EmptyView {
    init(_ category: TerminalSettingsCategory, subpage: TerminalSettingsSubpage? = nil, open: @escaping (TerminalSettingsSubpage) -> Void = { _ in }) {
        self.init(category, subpage: subpage, open: open) { EmptyView() }
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

public extension View {
    /// What goes around terminal settings: why the last change was not
    /// applied, and what Import from Ghostty did. The issue floats over the
    /// bottom edge: a safe-area inset there would make the form measure
    /// every row, not just the visible ones, on each change and page switch.
    func terminalSettingsChrome() -> some View {
        overlay(alignment: .bottom) { IssueBar() }
            .modifier(GhosttyImportAlert())
    }

    /// A Settings form: grouped, its sections drawn straight on the window's
    /// material (on the iPhone and iPad, the app's backdrop) rather than on
    /// an opaque sheet of their own.
    func settingsForm() -> some View {
        #if os(macOS)
            formStyle(.grouped)
                .scrollContentBackground(.hidden)
        #else
            formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(RXBackdrop().ignoresSafeArea())
        #endif
    }
}

/// What Advanced's Import from Ghostty, or the move of an earlier release's
/// settings, found.
private struct GhosttyImportAlert: ViewModifier {
    private var settings: TerminalSettings {
        .shared
    }

    func body(content: Content) -> some View {
        let shown = Binding { settings.lastImport != nil } set: { if !$0 { settings.lastImport = nil } }
        let result = settings.lastImport
        content.alert(
            title(result),
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

    private func title(_ result: TerminalSettings.GhosttyImport?) -> Text {
        if result?.earlierRelease == true {
            Text("Terminal settings moved from an earlier version", bundle: .module)
        } else if result?.found == false {
            Text("No Ghostty configuration found", bundle: .module)
        } else {
            Text("Imported from Ghostty", bundle: .module)
        }
    }
}

#if os(iOS)
    /// Undo and Redo for terminal settings in the navigation bar: without a
    /// keyboard, a slider or theme change has no ⌘Z or Edit menu to undo it.
    public struct TerminalSettingsUndoButtons: View {
        private var settings: TerminalSettings {
            .shared
        }

        public init() {}

        public var body: some View {
            // Read so a change, an undo or a redo redraws what is enabled.
            let _ = settings.config
            Button { settings.undoManager.undo() } label: { Label(String(localized: "Undo", bundle: .module), systemImage: "arrow.uturn.backward") }
                .disabled(!settings.undoManager.canUndo)
            Button { settings.undoManager.redo() } label: { Label(String(localized: "Redo", bundle: .module), systemImage: "arrow.uturn.forward") }
                .disabled(!settings.undoManager.canRedo)
        }
    }
#endif
