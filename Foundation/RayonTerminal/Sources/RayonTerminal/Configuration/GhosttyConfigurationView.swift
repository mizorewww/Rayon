#if os(macOS)
    import AppKit
#endif
import SwiftUI

/// Which category Settings shows, and the ones it showed before. The app can
/// hold one to open Settings at a category.
@MainActor
public final class ConfigNavigation: ObservableObject {
    @Published public private(set) var selection: String
    @Published private var history: [String]
    @Published private var index = 0

    public init(_ selection: String = "general") {
        self.selection = selection
        history = [selection]
    }

    public func go(_ id: String) {
        guard id != selection else { return }
        history = Array(history.prefix(index + 1)) + [id]
        index = history.count - 1
        selection = id
    }

    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index + 1 < history.count }

    func step(_ delta: Int) {
        let next = index + delta
        guard history.indices.contains(next) else { return }
        index = next
        selection = history[next]
    }
}

/// Rows the app supplies for a group in `SettingsLayout` (General,
/// Connection, About), so its preferences share Settings without coupling
/// this package to RayonStore.
public struct ConfigHostSettingsSection: Identifiable {
    public let id: String
    let keywords: String
    let content: AnyView

    @MainActor public init<Content: View>(id: String, keywords: String, @ViewBuilder content: () -> Content) {
        self.id = id
        self.keywords = keywords
        self.content = AnyView(content())
    }
}

/// All of Settings: the categories in a sidebar list, the selected one as a
/// form, the live terminal preview above the terminal's categories, and
/// search across every setting. The categories, their order and groups come
/// from `SettingsLayout`; Ghostty settings are drawn from the catalog, the
/// app's rows from `hostSections`.
public struct GhosttyConfigurationView: View {
    @StateObject private var ownNavigation: ConfigNavigation
    private let externalNavigation: ConfigNavigation?
    private let embedded: Bool
    /// False while the app keeps Settings out of sight: it then adds nothing
    /// to the window toolbar.
    private let active: Bool
    private let hostSections: [String: ConfigHostSettingsSection]
    private let onApplied: ((Double?) -> Void)?

    public init(
        embedded: Bool = false,
        hostSections: [ConfigHostSettingsSection] = [],
        navigation: ConfigNavigation? = nil,
        active: Bool = true,
        onApplied: ((Double?) -> Void)? = nil
    ) {
        self.hostSections = Dictionary(hostSections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        externalNavigation = navigation
        _ownNavigation = StateObject(wrappedValue: ConfigNavigation(hostSections.isEmpty ? "text" : "general"))
        self.embedded = embedded
        self.active = active
        self.onApplied = onApplied
    }

    public var body: some View {
        SettingsShell(
            navigation: externalNavigation ?? ownNavigation,
            categories: categories,
            hostSections: hostSections,
            embedded: embedded,
            active: active
        )
        .onAppear {
            if let onApplied { TerminalSettings.shared.onFontSizeChange = { onApplied($0) } }
        }
    }

    /// Categories with something to show: app categories need their rows.
    private var categories: [SettingsLayout.Category] {
        SettingsLayout.categories.filter { category in
            category.groups.contains { group in
                group.items.contains { item in
                    switch item {
                    case let .setting(key): SettingCatalog.shared.setting(key) != nil
                    case let .host(id): hostSections[id] != nil
                    }
                }
            }
        }
    }
}

private struct SettingsShell: View {
    @ObservedObject var navigation: ConfigNavigation
    let categories: [SettingsLayout.Category]
    let hostSections: [String: ConfigHostSettingsSection]
    let embedded: Bool
    let active: Bool
    private var settings: TerminalSettings { .shared }
    @State private var search = ""
    @State private var showsPreview = true
    @State private var confirmReset = false

    private var selected: SettingsLayout.Category? { categories.first { $0.id == navigation.selection } }

    var body: some View {
        content
            .safeAreaInset(edge: .bottom) { IssueBar() }
            .confirmationDialog("Reset every terminal setting to its default?", isPresented: $confirmReset) {
                Button("Reset", role: .destructive) { settings.resetAll() }
            } message: {
                Text("Rayon's General and Connection preferences are kept.")
            }
            .onAppear {
                #if DEBUG
                    if let text = ProcessInfo.processInfo.environment["RAYON_PREVIEW_SEARCH"] { search = text }
                #endif
                if !categories.contains(where: { $0.id == navigation.selection }) {
                    navigation.go(categories.first?.id ?? "text")
                }
            }
    }

    // MARK: Layout

    #if os(macOS)
        @ViewBuilder private var content: some View {
            HStack(spacing: 0) {
                List(selection: Binding(get: { search.isEmpty ? navigation.selection : nil }, set: { id in
                    guard let id else { return }
                    search = ""
                    navigation.go(id)
                })) {
                    ForEach([SettingsLayout.Category.Section.app, .terminal, .info], id: \.self) { section in
                        let members = categories.filter { $0.section == section }
                        if !members.isEmpty {
                            Section(section.rawValue) {
                                ForEach(members) { category in
                                    Label(category.title, systemImage: category.icon)
                                        .badge(changedCount(category))
                                        .tag(category.id)
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 200)
                Divider()
                detail
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar {
                if active {
                    ToolbarItemGroup(placement: .navigation) {
                        Button { navigation.step(-1) } label: { Label("Back", systemImage: "chevron.left") }
                            .disabled(!navigation.canGoBack)
                            .help("Previous category")
                        Button { navigation.step(1) } label: { Label("Forward", systemImage: "chevron.right") }
                            .disabled(!navigation.canGoForward)
                            .help("Next category")
                    }
                    ToolbarItemGroup(placement: .primaryAction) { tools }
                }
            }
            .modifier(SearchField(text: $search, active: active))
            .onChange(of: active) { _, now in if !now { search = "" } }
            .frame(minWidth: embedded ? 700 : 960, minHeight: 560)
        }
    #else
        @ViewBuilder private var content: some View {
            Group {
                if search.isEmpty {
                    List {
                        ForEach([SettingsLayout.Category.Section.app, .terminal, .info], id: \.self) { section in
                            let members = categories.filter { $0.section == section }
                            if !members.isEmpty {
                                Section(section.rawValue) {
                                    ForEach(members) { category in
                                        NavigationLink {
                                            CategoryPage(category: category, hostSections: hostSections, showsPreview: $showsPreview)
                                                .navigationTitle(category.title)
                                                .toolbar { ToolbarItem(placement: .primaryAction) { moreMenu } }
                                        } label: {
                                            Label(category.title, systemImage: category.icon)
                                                .badge(changedCount(category))
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    SearchResults(query: search, categories: categories, hostSections: hostSections) { category in
                        search = ""
                        navigation.go(category)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search settings")
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .primaryAction) { moreMenu } }
        }

        private var moreMenu: some View {
            Menu {
                tools
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    #endif

    @ViewBuilder private var detail: some View {
        if !search.isEmpty {
            SearchResults(query: search, categories: categories, hostSections: hostSections) { category in
                search = ""
                navigation.go(category)
            }
        } else if let selected {
            CategoryPage(category: selected, hostSections: hostSections, showsPreview: $showsPreview)
                .id(selected.id)
        } else {
            ContentUnavailableView("Choose a category", systemImage: "slider.horizontal.3")
        }
    }

    /// Undo, Redo, Reset, the preview and the file.
    @ViewBuilder private var tools: some View {
        let _ = settings.revision
        let terminal = selected?.section == .terminal || !search.isEmpty
        Button { settings.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
            .disabled(!settings.undoManager.canUndo)
            .help("Undo the last terminal setting change")
        Button { settings.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
            .disabled(!settings.undoManager.canRedo)
            .help("Redo")
        Toggle(isOn: $showsPreview.animation()) { Label("Preview", systemImage: "rectangle.topthird.inset.filled") }
            .disabled(!(selected?.previews ?? false) || !search.isEmpty)
            .help(showsPreview ? "Hide the terminal preview" : "Show a terminal preview above the settings")
        #if os(macOS)
            Button { NSWorkspace.shared.activateFileViewerSelecting([settings.fileURL]) } label: {
                Label("Show config.ghostty in Finder", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(!FileManager.default.fileExists(atPath: settings.fileURL.path))
            .help("The file the terminal settings are kept in")
        #else
            if FileManager.default.fileExists(atPath: settings.fileURL.path) {
                ShareLink(item: settings.fileURL) { Label("Share config.ghostty", systemImage: "square.and.arrow.up") }
            }
        #endif
        Button(role: .destructive) { confirmReset = true } label: {
            Label("Reset Terminal Settings…", systemImage: "arrow.counterclockwise")
        }
        .disabled(!terminal)
        .help("Reset every terminal setting to its default")
    }

    private func changedCount(_ category: SettingsLayout.Category) -> Int {
        category.keys.filter(settings.isSet).count
    }
}

#if os(macOS)
    private struct SearchField: ViewModifier {
        @Binding var text: String
        let active: Bool

        func body(content: Content) -> some View {
            if active {
                content.searchable(text: $text, placement: .toolbar, prompt: "Search settings")
            } else {
                content
            }
        }
    }
#endif

// MARK: - Pages

/// One category as a form: its groups as sections, the app's rows and
/// Ghostty settings alike, with the terminal preview above when it helps.
private struct CategoryPage: View {
    let category: SettingsLayout.Category
    let hostSections: [String: ConfigHostSettingsSection]
    @Binding var showsPreview: Bool

    var body: some View {
        VStack(spacing: 0) {
            if category.previews, showsPreview {
                TerminalPreview()
                    .frame(height: 168)
                    .padding([.horizontal, .top])
                    .transition(.opacity)
            }
            Form {
                if let note = category.note {
                    Section { Text(note).foregroundStyle(.secondary) }
                }
                ForEach(category.groups) { group in
                    GroupSection(group: group, keys: group.keys, hostSections: hostSections)
                }
            }
            .formStyle(.grouped)
        }
    }
}

/// A group: the app's rows, then its Ghostty settings.
private struct GroupSection: View {
    let group: SettingsLayout.Group
    let keys: [String]
    let hostSections: [String: ConfigHostSettingsSection]
    var query = ""

    var body: some View {
        let hosts = group.items.compactMap { item -> ConfigHostSettingsSection? in
            if case let .host(id) = item { return hostSections[id] }
            return nil
        }
        let settings = keys.compactMap { SettingCatalog.shared.setting($0) }
        if keys == ["keybind"], query.isEmpty || SearchResults.shortcutsMatch(query) {
            KeybindingList(query: query)
        } else if !hosts.isEmpty || !settings.isEmpty {
            Section {
                ForEach(hosts) { $0.content }
                ForEach(settings) { SettingRow(setting: $0, query: query) }
            } header: {
                Text(group.title)
            } footer: {
                if let footer = group.footer { Text(footer) }
            }
        }
    }
}

/// Every setting and app group matching all the words typed, under their
/// categories, each with a way to its category.
private struct SearchResults: View {
    let query: String
    let categories: [SettingsLayout.Category]
    let hostSections: [String: ConfigHostSettingsSection]
    let show: (String) -> Void

    private var tokens: [Substring] { query.lowercased().split(whereSeparator: \.isWhitespace) }

    private func matches(_ text: String) -> Bool {
        let text = text.lowercased()
        return tokens.allSatisfy { text.contains($0) }
    }

    /// Whether a shortcut in use answers `query` by its keys or its action.
    static func shortcutsMatch(_ query: String) -> Bool {
        TerminalSettings.shared.shortcuts.contains { raw in
            let binding = Keybinding(raw)
            return KeybindingNames.applies(binding) && KeybindingNames.contains(KeybindingNames.searchText(binding, raw: raw), every: query)
        }
    }

    private func settingMatches(_ key: String, in category: SettingsLayout.Category, _ group: SettingsLayout.Group) -> Bool {
        if key == "keybind", Self.shortcutsMatch(query) { return true }
        guard let setting = SettingCatalog.shared.setting(key) else { return false }
        let options = (setting.widget?.options ?? []).map { SettingsLayout.optionName(key, value: $0.value, fallback: $0.name) }
        return matches(([setting.key, setting.name, setting.plainDescription, SettingsLayout.title(setting),
                         SettingsLayout.summary(setting), category.title, group.title] + options).joined(separator: " "))
    }

    var body: some View {
        let results = categories.compactMap { category -> (SettingsLayout.Category, [(SettingsLayout.Group, [String])])? in
            let groups = category.groups.compactMap { group -> (SettingsLayout.Group, [String])? in
                let hostMatch = group.items.contains { item in
                    guard case let .host(id) = item, let host = hostSections[id] else { return false }
                    return matches("\(category.title) \(group.title) \(host.keywords)")
                }
                let keys = group.keys.filter { settingMatches($0, in: category, group) }
                return hostMatch || !keys.isEmpty ? (group, keys) : nil
            }
            return groups.isEmpty ? nil : (category, groups)
        }
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            Form {
                ForEach(results, id: \.0.id) { category, groups in
                    Section {
                        Button("Show \(category.title)", systemImage: category.icon) { show(category.id) }
                    }
                    ForEach(groups, id: \.0.id) { group, keys in
                        GroupSection(
                            group: SettingsLayout.Group(group.id, "\(category.title) › \(group.title)", group.items),
                            keys: keys,
                            hostSections: group.items.contains { if case .host = $0 { true } else { false } } ? hostSections : [:],
                            query: query
                        )
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

/// Why the last change was not applied, until it is dismissed or one is.
private struct IssueBar: View {
    private var settings: TerminalSettings { .shared }

    var body: some View {
        if let issue = settings.issue {
            HStack(alignment: .firstTextBaseline) {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .textSelection(.enabled)
                Spacer()
                Button { settings.issue = nil } label: { Label("Dismiss", systemImage: "xmark") }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding()
        }
    }
}
