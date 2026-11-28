import SwiftUI

/// A category's page, or one of its subpages, as a form: its groups as
/// sections, rows that open its subpages, and Restore Defaults.
struct CategoryPage: View {
    let category: SettingsLayout.Category
    /// The group shown as a page of its own; nil for the category's page.
    var subpage: String?
    var header: AnyView?
    var open: (TerminalSettingsSubpage) -> Void = { _ in }
    #if os(macOS)
        @State private var formHeight: CGFloat?
    #endif

    /// What this page shows itself: the category's groups but its subpages,
    /// or the subpage's group.
    private var groups: [SettingsLayout.Group] {
        if let subpage { category.groups.filter { $0.id == subpage } } else { category.groups.filter { !$0.isSubpage } }
    }

    var body: some View {
        #if os(macOS)
            if subpage == nil, category.keys.contains("keybind") {
                shortcutsPage
            } else {
                form(groups)
            }
        #else
            form(groups)
        #endif
    }

    private func form(_ groups: [SettingsLayout.Group]) -> some View {
        Form {
            header
            ForEach(groups) { group in
                GroupSection(group: group, keys: group.keys)
            }
            if subpage == nil {
                SubpageLinks(category: category, open: open)
            }
            if !groups.contains(where: { $0.keys == ["keybind"] }) {
                RestoreDefaults(keys: groups.flatMap(\.keys), resetsAll: subpage == nil && category.id == "advanced")
            }
        }
        .settingsForm()
    }

    #if os(macOS)
        /// A Table cannot sit inside a Form: the page's other groups go in a
        /// form as tall as its rows, the shortcuts in a table below it.
        private var shortcutsPage: some View {
            VStack(spacing: 0) {
                form(groups.filter { $0.keys != ["keybind"] })
                    .scrollDisabled(true)
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { formHeight = $1 }
                    .frame(height: formHeight)
                KeybindingList(table: true)
            }
        }
    #endif
}

/// The rows that open a category's subpages, each marked while any of its
/// settings is changed.
private struct SubpageLinks: View {
    let category: SettingsLayout.Category
    let open: (TerminalSettingsSubpage) -> Void
    private var settings: TerminalSettings {
        .shared
    }

    var body: some View {
        let subpages = TerminalSettingsCategory.all.first { $0.id == category.id }?.subpages ?? []
        if !subpages.isEmpty {
            Section {
                ForEach(subpages) { subpage in
                    let group = category.groups.first { $0.id == subpage.group }
                    let modified = group?.keys.contains(where: settings.isSet) ?? false
                    #if os(macOS)
                        Button { open(subpage) } label: {
                            HStack {
                                SubpageTitle(title: subpage.title, modified: modified)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    #else
                        NavigationLink(value: subpage) {
                            SubpageTitle(title: subpage.title, modified: modified)
                        }
                    #endif
                }
            }
        }
    }
}

private struct SubpageTitle: View {
    let title: String
    let modified: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if modified { ModifiedMark() }
        }
    }
}

/// Puts the page's settings back to their defaults, after asking. On
/// Advanced, also every terminal setting, and on the Mac Import from Ghostty.
private struct RestoreDefaults: View {
    let keys: [String]
    let resetsAll: Bool
    @State private var confirmingPage = false
    @State private var confirmingAll = false
    private var settings: TerminalSettings {
        .shared
    }

    var body: some View {
        Section {} footer: {
            // In a row while they fit, else stacked: longer languages
            // would truncate them.
            ViewThatFits(in: .horizontal) {
                HStack {
                    Spacer()
                    buttons
                }
                VStack(alignment: .trailing) {
                    buttons
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .confirmationDialog(Text("Reset every terminal setting to its default?", bundle: .module), isPresented: $confirmingAll) {
                Button(.init("Reset", bundle: .module), role: .destructive) { settings.resetAll() }
            } message: {
                Text("Only the terminal's settings are reset; Rayon's own are kept.", bundle: .module)
            }
            .confirmationDialog(Text("Restore the default settings on this page?", bundle: .module), isPresented: $confirmingPage) {
                Button(.init("Restore Defaults", bundle: .module), role: .destructive) { settings.reset(keys) }
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        if resetsAll {
            #if os(macOS)
                Button(.init("Import from Ghostty…", bundle: .module)) { settings.importFromGhostty() }
                    .help(.init("Take the settings Rayon's terminal uses from Ghostty's configuration", bundle: .module))
            #endif
            Button(.init("Reset All Terminal Settings…", bundle: .module)) { confirmingAll = true }
        }
        Button(.init("Restore Defaults…", bundle: .module)) { confirmingPage = true }
            .disabled(!keys.contains(where: settings.isSet))
    }
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
                .settingsForm()
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
