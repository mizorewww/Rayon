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

    public var canGoBack: Bool {
        index > 0
    }

    public var canGoForward: Bool {
        index + 1 < history.count
    }

    public func step(_ delta: Int) {
        let next = index + delta
        guard history.indices.contains(next) else { return }
        index = next
        selection = history[next]
    }
}

/// The terminal's settings on their own, for the configuration preview:
/// the categories in a list, the selected one as a form with the live
/// terminal preview, and search across every setting. Rayon's Settings
/// arranges the same parts (`TerminalSettingsPage` and the rest) itself.
public struct GhosttyConfigurationView: View {
    @StateObject private var navigation = ConfigNavigation("text")

    public init() {}

    public var body: some View {
        SettingsShell(navigation: navigation, categories: SettingsLayout.categories)
    }
}

private struct SettingsShell: View {
    @ObservedObject var navigation: ConfigNavigation
    let categories: [SettingsLayout.Category]
    private var settings: TerminalSettings {
        .shared
    }

    @State private var search = ""
    @State private var showsPreview = true
    @State private var confirmReset = false

    private var selected: SettingsLayout.Category? {
        categories.first { $0.id == navigation.selection }
    }

    var body: some View {
        content
            .terminalSettingsChrome(confirmingReset: $confirmReset)
            .onAppear {
                #if DEBUG
                    if let text = ProcessInfo.processInfo.environment["RAYON_PREVIEW_SEARCH"] {
                        search = text
                    }
                #endif
                if !categories.contains(where: { $0.id == navigation.selection }) {
                    navigation.go(categories.first?.id ?? "text")
                }
            }
    }

    // MARK: Layout

    #if os(macOS)
        private var content: some View {
            HStack(spacing: 0) {
                List(selection: Binding(get: { search.isEmpty ? navigation.selection : nil }, set: { id in
                    guard let id else { return }
                    search = ""
                    navigation.go(id)
                })) {
                    ForEach(categories) { category in
                        Label(category.title, systemImage: category.icon)
                            .badge(changedCount(category))
                            .tag(category.id)
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 200)
                Divider()
                detail
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button { navigation.step(-1) } label: { Label(.init("Back", bundle: .module), systemImage: "chevron.left") }
                        .disabled(!navigation.canGoBack)
                        .help(.init("Previous category", bundle: .module))
                    Button { navigation.step(1) } label: { Label(.init("Forward", bundle: .module), systemImage: "chevron.right") }
                        .disabled(!navigation.canGoForward)
                        .help(.init("Next category", bundle: .module))
                }
                ToolbarItemGroup(placement: .primaryAction) { tools }
            }
            .searchable(text: $search, placement: .toolbar, prompt: Text("Search settings", bundle: .module))
            .frame(minWidth: 960, minHeight: 560)
        }
    #else
        private var content: some View {
            Group {
                if search.isEmpty {
                    List {
                        ForEach(categories) { category in
                            NavigationLink {
                                CategoryPage(category: category, showsPreview: $showsPreview)
                                    .navigationTitle(category.title)
                                    .toolbar { ToolbarItem(placement: .primaryAction) { moreMenu } }
                            } label: {
                                Label(category.title, systemImage: category.icon)
                                    .badge(changedCount(category))
                            }
                        }
                    }
                } else {
                    SearchResults(query: search, categories: categories) { category in
                        search = ""
                        navigation.go(category)
                    }
                }
            }
            .searchable(text: $search, prompt: Text("Search settings", bundle: .module))
            .navigationTitle(.init("Settings", bundle: .module))
            .toolbar { ToolbarItem(placement: .primaryAction) { moreMenu } }
        }

        private var moreMenu: some View {
            Menu {
                tools
            } label: {
                Label(.init("More", bundle: .module), systemImage: "ellipsis.circle")
            }
        }
    #endif

    @ViewBuilder private var detail: some View {
        if !search.isEmpty {
            SearchResults(query: search, categories: categories) { category in
                search = ""
                navigation.go(category)
            }
        } else if let selected {
            CategoryPage(category: selected, showsPreview: $showsPreview)
                .id(selected.id)
        } else {
            ContentUnavailableView(String(localized: "Choose a category", bundle: .module), systemImage: "slider.horizontal.3")
        }
    }

    private var tools: some View {
        TerminalSettingsTools(
            showsPreview: $showsPreview,
            confirmingReset: $confirmReset,
            previewAvailable: (selected?.previews ?? false) && search.isEmpty,
            resetAvailable: true
        )
    }

    private func changedCount(_ category: SettingsLayout.Category) -> Int {
        category.keys.filter(settings.isSet).count
    }
}

// MARK: - Pages

/// One category as a form: its groups as sections, with the terminal preview above when it helps.
struct CategoryPage: View {
    let category: SettingsLayout.Category
    @Binding var showsPreview: Bool
    var header: AnyView?
    #if os(macOS)
        @State private var formHeight: CGFloat?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if category.previews, showsPreview {
                TerminalPreview()
                    .frame(height: 168)
                    .padding([.horizontal, .top])
                    .transition(.opacity)
            }
            #if os(macOS)
                if category.keys.contains("keybind") {
                    shortcutsPage
                } else {
                    form(category.groups)
                }
            #else
                form(category.groups)
            #endif
        }
    }

    private func form(_ groups: [SettingsLayout.Group]) -> some View {
        Form {
            header
            ForEach(groups) { group in
                GroupSection(group: group, keys: group.keys)
            }
        }
        .formStyle(.grouped)
    }

    #if os(macOS)
        /// A Table cannot sit inside a Form: the page's other groups go in a
        /// form as tall as its rows, the shortcuts in a table below it.
        private var shortcutsPage: some View {
            VStack(spacing: 0) {
                form(category.groups.filter { $0.keys != ["keybind"] })
                    .scrollDisabled(true)
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { formHeight = $1 }
                    .frame(height: formHeight)
                KeybindingList(table: true)
            }
        }
    #endif
}

/// A group of Ghostty settings.
private struct GroupSection: View {
    let group: SettingsLayout.Group
    let keys: [String]
    var query = ""

    var body: some View {
        let settings = keys.compactMap { SettingCatalog.shared.setting($0) }
        if keys == ["keybind"], query.isEmpty || SearchResults.shortcutsMatch(query) {
            KeybindingList(query: query)
        } else if !settings.isEmpty {
            Section {
                ForEach(settings) { SettingRow(setting: $0, query: query) }
            } header: {
                Text(group.title)
            } footer: {
                if let footer = group.footer {
                    Text(footer)
                }
            }
        }
    }
}

/// Every setting matching all the words typed, under their
/// categories, each with a way to its category.
struct SearchResults: View {
    let query: String
    let categories: [SettingsLayout.Category]
    let show: (String) -> Void

    private var tokens: [Substring] {
        query.lowercased().split(whereSeparator: \.isWhitespace)
    }

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
        if key == "keybind", Self.shortcutsMatch(query) {
            return true
        }
        guard let setting = SettingCatalog.shared.setting(key) else { return false }
        let options = (setting.widget?.options ?? []).map { SettingsLayout.optionName(key, value: $0.value, fallback: $0.name) }
        return matches(([setting.key, setting.name, setting.plainDescription, SettingsLayout.title(setting),
                         SettingsLayout.summary(setting), category.title, group.title] + options).joined(separator: " "))
    }

    /// The groups with a match, under their categories.
    var results: [(SettingsLayout.Category, [(SettingsLayout.Group, [String])])] {
        categories.compactMap { category -> (SettingsLayout.Category, [(SettingsLayout.Group, [String])])? in
            let groups = category.groups.compactMap { group -> (SettingsLayout.Group, [String])? in
                let keys = group.keys.filter { settingMatches($0, in: category, group) }
                return keys.isEmpty ? nil : (group, keys)
            }
            return groups.isEmpty ? nil : (category, groups)
        }
    }

    var body: some View {
        let results = results
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            Form { sections(results) }
                .formStyle(.grouped)
        }
    }

    /// The results as form sections, for a form that shows more.
    func sections(_ results: [(SettingsLayout.Category, [(SettingsLayout.Group, [String])])]) -> some View {
        ForEach(results, id: \.0.id) { category, groups in
            Section {
                Button(.init("Show \(category.title)", bundle: .module), systemImage: category.icon) { show(category.id) }
            }
            ForEach(groups, id: \.0.id) { group, keys in
                GroupSection(
                    group: SettingsLayout.Group(group.id, "\(category.title) › \(group.title)", keys: group.keys),
                    keys: keys,
                    query: query
                )
            }
        }
    }
}

/// Why the last change was not applied, until it is dismissed or one is.
struct IssueBar: View {
    private var settings: TerminalSettings {
        .shared
    }

    var body: some View {
        if let issue = settings.issue {
            HStack(alignment: .firstTextBaseline) {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .textSelection(.enabled)
                Spacer()
                Button { settings.issue = nil } label: { Label(.init("Dismiss", bundle: .module), systemImage: "xmark") }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding()
        }
    }
}
