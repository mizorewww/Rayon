import SwiftUI

// MARK: - Pages

/// One category as a form: its groups as sections.
struct CategoryPage: View {
    let category: SettingsLayout.Category
    var header: AnyView?
    #if os(macOS)
        @State private var formHeight: CGFloat?
    #endif

    var body: some View {
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
/// categories, each with a way to its category. The matches are worked out
/// once, when it is made.
struct SearchResults: View {
    /// A category with a match, and its groups with their matching keys.
    typealias Match = (SettingsLayout.Category, [(SettingsLayout.Group, [String])])

    let query: String
    let results: [Match]
    let show: (String) -> Void

    init(query: String, categories: [SettingsLayout.Category], show: @escaping (String) -> Void) {
        self.init(query: query, results: Self.results(for: query, in: categories), show: show)
    }

    init(query: String, results: [Match], show: @escaping (String) -> Void) {
        self.query = query
        self.results = results
        self.show = show
    }

    /// Whether a shortcut in use answers `query` by its keys or its action.
    static func shortcutsMatch(_ query: String) -> Bool {
        TerminalSettings.shared.shortcuts.contains { raw in
            let binding = Keybinding(raw)
            return KeybindingNames.applies(binding) && KeybindingNames.contains(KeybindingNames.searchText(binding, raw: raw), every: query)
        }
    }

    /// The groups with a match, under their categories.
    static func results(for query: String, in categories: [SettingsLayout.Category]) -> [Match] {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace)
        // Asked once: it reads every shortcut in use.
        let shortcutsMatch = categories.contains { $0.keys.contains("keybind") } && Self.shortcutsMatch(query)
        func settingMatches(_ key: String, in category: SettingsLayout.Category, _ group: SettingsLayout.Group) -> Bool {
            if key == "keybind", shortcutsMatch {
                return true
            }
            guard let setting = SettingCatalog.shared.setting(key) else { return false }
            let options = (setting.widget?.options ?? []).map { SettingsLayout.optionName(key, value: $0.value, fallback: $0.name) }
            let text = ([setting.key, setting.name, setting.plainDescription, SettingsLayout.title(setting),
                         SettingsLayout.summary(setting), category.title, group.title] + options).joined(separator: " ").lowercased()
            return tokens.allSatisfy { text.contains($0) }
        }
        return categories.compactMap { category -> Match? in
            let groups = category.groups.compactMap { group -> (SettingsLayout.Group, [String])? in
                let keys = group.keys.filter { settingMatches($0, in: category, group) }
                return keys.isEmpty ? nil : (group, keys)
            }
            return groups.isEmpty ? nil : (category, groups)
        }
    }

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            Form { sections(results) }
                .formStyle(.grouped)
        }
    }

    /// The results as form sections, for a form that shows more.
    func sections(_ results: [Match]) -> some View {
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
