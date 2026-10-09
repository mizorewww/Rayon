import AppKit
import RayonDesign
import SwiftUI

/// Rows the app supplies for a group in `ConfigLayout` (General, Connection,
/// About), so its preferences share Settings without coupling this package to
/// RayonStore. The content is the group's rows, usually an `RXDividedStack`.
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

/// All of Settings: a category column, then the selected category's groups as
/// cards. The categories, their order and their groups come from `ConfigLayout`;
/// Ghostty settings are drawn from the catalog, app rows from `hostSections`.
public struct GhosttyConfigurationView: View {
    @StateObject private var model = ConfigEditorModel.shared
    @Binding private var selectionBinding: String
    @State private var localSelection: String
    @State private var search = ""
    @State private var jumpTarget: String?
    @State private var showPreview = true
    @State private var resetConfirm = false
    @State private var navigationHistory = ["general"]
    @State private var navigationIndex = 0
    @State private var navigating = false
    private let onApplied: ((Double?) -> Void)?
    private let embedded: Bool
    private let usesExternalSelection: Bool
    private let hostSections: [String: ConfigHostSettingsSection]

    private var selection: String {
        get { usesExternalSelection ? selectionBinding : localSelection }
        nonmutating set {
            if usesExternalSelection { selectionBinding = newValue } else { localSelection = newValue }
        }
    }

    /// Categories with something to show: app categories need their host rows.
    private var categories: [ConfigLayout.Category] {
        ConfigLayout.categories.filter { category in
            category.groups.contains { group in
                group.items.contains { item in
                    switch item {
                    case let .setting(key): return ConfigCatalog.shared.setting(key: key) != nil
                    case let .host(id): return hostSections[id] != nil
                    }
                }
            }
        }
    }

    private var category: ConfigLayout.Category? { categories.first { $0.id == selection } }

    public init(
        embedded: Bool = false,
        hostSections: [ConfigHostSettingsSection] = [],
        selection: Binding<String>? = nil,
        onApplied: ((Double?) -> Void)? = nil
    ) {
        self.hostSections = Dictionary(hostSections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let fallback = hostSections.isEmpty ? "text" : "general"
        let initialSelection = selection?.wrappedValue ?? fallback
        _localSelection = State(initialValue: initialSelection)
        _selectionBinding = selection ?? .constant(initialSelection)
        usesExternalSelection = selection != nil
        _navigationHistory = State(initialValue: [initialSelection])
        self.embedded = embedded
        self.onApplied = onApplied
        _showPreview = State(initialValue: !embedded)
    }

    private func installApplyHandler() {
        model.onApplied = onApplied
    }

    private var showsTerminalTools: Bool { search.isEmpty ? category?.section == .terminal : true }

    public var body: some View {
        HStack(spacing: 0) {
            categoryColumn
                .frame(width: 216)
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: RX.Space.s4) {
                    content
                        .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                    if showPreview, search.isEmpty, category?.previews == true {
                        ScrollView {
                            ConfigPreview(model: model)
                                .rxCard(padding: 0)
                                .padding(.bottom, RX.Space.s6)
                        }
                        .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
                        .padding(.trailing, RX.Space.s6)
                        .padding(.top, RX.Space.s3)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                if !model.message.isEmpty {
                    errorBar
                }
            }
        }
        .background(RXWindowBackground().ignoresSafeArea())
        .toolbarBackground(.hidden, for: .windowToolbar)
        .modifier(ConfigToolbar(leading: {
            ControlGroup {
                Button { navigate(-1) } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(navigationIndex == 0)
                    .help("Previous category")
                Button { navigate(1) } label: { Label("Forward", systemImage: "chevron.right") }
                    .disabled(navigationIndex + 1 >= navigationHistory.count)
                    .help("Next category")
            }
        }, trailing: {
            Group {
                if showsTerminalTools {
                    ControlGroup {
                        Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                            .disabled(model.undoStack.isEmpty)
                            .help("Undo the last terminal setting change")
                        Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                            .disabled(model.redoStack.isEmpty)
                            .help("Redo")
                    }
                    Button { resetConfirm = true } label: {
                        Label("Reset Terminal…", systemImage: "arrow.counterclockwise").labelStyle(.titleAndIcon)
                    }
                    .help("Reset every terminal setting to its default")
                    if category?.previews == true {
                        Toggle(isOn: $showPreview.animation(.easeInOut(duration: 0.25))) {
                            Label("Preview", systemImage: "sidebar.right").labelStyle(.titleAndIcon)
                        }
                        .toggleStyle(.button)
                        .help(showPreview ? "Hide the live terminal preview" : "Show a live terminal preview beside the settings")
                    }
                }
            }
        }))
        .searchable(text: $search, placement: .toolbar, prompt: "Search settings")
        .onAppear {
            installApplyHandler()
            if category == nil { selection = categories.first?.id ?? "text" }
        }
        .animation(.easeOut(duration: 0.18), value: selection)
        .animation(.easeOut(duration: 0.18), value: search.isEmpty)
        .onChange(of: selection) { next in
            if navigating { navigating = false; return }
            navigationHistory = Array(navigationHistory.prefix(navigationIndex + 1)) + [next]
            navigationIndex = navigationHistory.count - 1
        }
        .confirmationDialog("Reset every terminal setting to its default?", isPresented: $resetConfirm) {
            Button("Reset Terminal Settings", role: .destructive) { model.edit { $0 = ConfigDocument() } }
        } message: {
            Text("Rayon's General and Connection preferences are kept.")
        }
        .frame(minWidth: embedded ? 700 : 960, minHeight: 560)
    }

    // MARK: Category column

    private var categoryColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach([ConfigLayout.Category.Section.app, .terminal, .info], id: \.self) { section in
                    let members = categories.filter { $0.section == section }
                    if !members.isEmpty {
                        if section.rawValue.isEmpty {
                            Spacer().frame(height: RX.Space.s4)
                        } else {
                            categorySection(section.rawValue)
                        }
                        ForEach(members) { category in
                            categoryRow(category)
                        }
                    }
                }
            }
            .padding(.horizontal, RX.Space.s2)
            .padding(.top, RX.Space.s3)
            .padding(.bottom, RX.Space.s4)
        }
    }

    private func categorySection(_ title: String) -> some View {
        Text(title)
            .font(.rxSectionLabel)
            .foregroundStyle(.rxInkSecondary)
            .padding(.horizontal, RX.Space.s3)
            .padding(.top, RX.Space.s4)
            .padding(.bottom, RX.Space.s1)
    }

    private func categoryRow(_ category: ConfigLayout.Category) -> some View {
        let selected = selection == category.id && search.isEmpty
        return Button {
            search = ""
            selection = category.id
        } label: {
            HStack(spacing: RX.Space.s2) {
                Image(systemName: category.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.rxAccent : Color.rxInkSecondary)
                    .frame(width: 18)
                Text(category.title)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .foregroundStyle(.rxInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
                let count = modifiedCount(category)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.rxAccent)
                        .help("\(count) changed from the default")
                }
            }
            .padding(.horizontal, RX.Space.s3)
            .frame(height: 30)
            .background(
                Capsule()
                    .fill(selected ? Color.primary.opacity(0.09) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func modifiedCount(_ category: ConfigLayout.Category) -> Int {
        model.document.overrides.keys.filter { ConfigLayout.categoryOfKey[$0]?.id == category.id }.count
    }

    // MARK: Errors

    /// Settings save automatically; only a failed save needs a word.
    private var errorBar: some View {
        HStack(spacing: RX.Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.rxWarning)
            Text(model.message)
                .font(.rxBody)
                .foregroundStyle(.rxInk)
                .textSelection(.enabled)
            Spacer()
            Button { model.message = "" } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, RX.Space.s4)
        .padding(.vertical, RX.Space.s3)
        .background(Color.clear.rxCard(padding: 0))
        .padding(.horizontal, RX.Space.s6)
        .padding(.bottom, RX.Space.s4)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if !search.isEmpty {
            searchContent
        } else if let category {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: RX.Space.s6) {
                        PageTitle(category.title)
                        if category.id == "keyboard" {
                            ConfigKeybindingList(model: model)
                        } else {
                            ForEach(category.groups) { group in
                                groupCard(group)
                            }
                        }
                    }
                    .frame(maxWidth: category.section == .terminal ? .infinity : 760, alignment: .leading)
                    .padding(.horizontal, RX.Space.s6)
                    .padding(.top, RX.Space.s3)
                    .padding(.bottom, RX.Space.s6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(category.id)
                .task(id: jumpTarget) {
                    guard let jumpTarget else { return }
                    await Task.yield()
                    proxy.scrollTo(jumpTarget, anchor: .top)
                }
            }
        } else {
            EmptyStateView("Choose a category", systemImage: "slider.horizontal.3")
                .frame(maxHeight: .infinity)
        }
    }

    /// A group: its caption, then its rows on one card.
    @ViewBuilder private func groupCard(_ group: ConfigLayout.Group, keys: [String]? = nil) -> some View {
        let hosts = group.items.compactMap { item -> ConfigHostSettingsSection? in
            if case let .host(id) = item { return hostSections[id] }
            return nil
        }
        let settings = (keys ?? group.items.compactMap { item -> String? in
            if case let .setting(key) = item { return key }
            return nil
        }).compactMap { ConfigCatalog.shared.setting(key: $0) }
        if !hosts.isEmpty || !settings.isEmpty {
            VStack(alignment: .leading, spacing: RX.Space.s2) {
                CapsLabel(group.title)
                    .padding(.leading, RX.Space.s4)
                VStack(spacing: 0) {
                    ForEach(hosts) { $0.content }
                    if !settings.isEmpty {
                        RXDividedStack {
                            ForEach(settings) { setting in
                                ConfigSettingRow(model: model, setting: setting, query: search).id(setting.key)
                            }
                        }
                    }
                }
                .padding(.horizontal, RX.Space.s4)
                .background(Color.clear.rxCard(padding: 0))
            }
        }
    }

    // MARK: Search

    private var searchContent: some View {
        let settings = searchResults
        let hosts = hostSearchResults
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: RX.Space.s6) {
                PageTitle("Search Results", subtitle: searchSubtitle(settings.count + hosts.count))
                ForEach(categories) { category in
                    let groups = category.groups.compactMap { group -> (ConfigLayout.Group, [String])? in
                        let hostMatch = group.items.contains { item in
                            if case let .host(id) = item { return hosts.contains(id) }
                            return false
                        }
                        let keys = group.items.compactMap { item -> String? in
                            if case let .setting(key) = item, settings.contains(key) { return key }
                            return nil
                        }
                        return hostMatch || !keys.isEmpty ? (group, keys) : nil
                    }
                    if !groups.isEmpty {
                        VStack(alignment: .leading, spacing: RX.Space.s3) {
                            HStack {
                                Label(category.title, systemImage: category.icon)
                                    .font(.rxBodyStrong)
                                    .foregroundStyle(.rxInk)
                                Spacer()
                                Button("Show in \(category.title)") {
                                    jumpTarget = groups.first?.1.first
                                    selection = category.id
                                    search = ""
                                }
                                .buttonStyle(.link)
                                .font(.rxHelp)
                            }
                            ForEach(groups, id: \.0.id) { group, keys in
                                groupCard(group, keys: keys)
                            }
                        }
                    }
                }
                if settings.isEmpty && hosts.isEmpty {
                    EmptyStateView("No settings match “\(search)”", systemImage: "magnifyingglass")
                        .rxCard()
                }
            }
            .padding(.horizontal, RX.Space.s6)
            .padding(.top, RX.Space.s3)
            .padding(.bottom, RX.Space.s6)
        }
    }

    private func searchSubtitle(_ count: Int) -> String {
        count == 0 ? "Nothing found" : "\(count) match\(count == 1 ? "" : "es") for “\(search)”"
    }

    private var tokens: [Substring] { search.lowercased().split(whereSeparator: \.isWhitespace) }

    /// Host groups whose keywords, group or category title match.
    private var hostSearchResults: Set<String> {
        var result = Set<String>()
        for category in categories {
            for group in category.groups {
                for case let .host(id) in group.items {
                    guard let section = hostSections[id] else { continue }
                    let text = "\(category.title) \(group.title) \(section.keywords)".lowercased()
                    if tokens.allSatisfy({ text.contains($0) }) { result.insert(id) }
                }
            }
        }
        return result
    }

    /// Ghostty keys whose name, description, key, group or category match.
    private var searchResults: Set<String> {
        let tokens = tokens
        var result = Set<String>()
        for category in categories {
            for group in category.groups {
                for case let .setting(key) in group.items {
                    guard let setting = ConfigCatalog.shared.setting(key: key) else { continue }
                    let wording = ConfigLayout.wording[key]
                    let haystack = [setting.key, setting.name, setting.description, wording?.title ?? "", wording?.summary ?? "", category.title, group.title]
                        .joined(separator: " ").lowercased()
                    if tokens.allSatisfy({ haystack.contains($0) }) { result.insert(key) }
                }
            }
        }
        return result
    }

    private func navigate(_ delta: Int) {
        let next = navigationIndex + delta
        guard navigationHistory.indices.contains(next) else { return }
        navigating = true; navigationIndex = next; selection = navigationHistory[next]
    }
}

/// Navigation at the leading edge, actions at the trailing edge of the window toolbar.
private struct ConfigToolbar<Leading: View, Trailing: View>: ViewModifier {
    let leading: Leading
    let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.toolbar {
                ToolbarItemGroup(placement: .navigation) { leading }
                ToolbarSpacer(.flexible)
                ToolbarItemGroup(placement: .automatic) { trailing }
            }
        } else {
            content.toolbar {
                ToolbarItemGroup(placement: .navigation) { leading }
                ToolbarItemGroup(placement: .automatic) { trailing }
            }
        }
    }
}
