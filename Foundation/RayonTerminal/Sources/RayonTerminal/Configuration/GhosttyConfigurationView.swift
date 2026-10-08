import AppKit
import RayonDesign
import SwiftUI

/// App-owned preferences share the editor's navigation without coupling this package to RayonStore.
public struct ConfigHostSettingsSection: Identifiable {
    public let id: String
    let title: String
    let subtitle: String?
    let icon: String
    let keywords: String
    let content: AnyView

    @MainActor public init<Content: View>(id: String, title: String, subtitle: String? = nil, icon: String, keywords: String,
                                        @ViewBuilder content: () -> Content) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.keywords = keywords
        self.content = AnyView(content())
    }
}

/// The terminal settings Rayon applies, drawn with the Rayon design system: a
/// category column, then the selected category's settings as grouped cards.
/// Settings that only matter to standalone Ghostty are not shown.
public struct GhosttyConfigurationView: View {
    @StateObject private var model = ConfigEditorModel.shared
    @Binding private var selectionBinding: String
    @State private var localSelection: String
    @State private var search = ""
    @State private var jumpTarget: String?
    @State private var showPreview = true
    @State private var resetConfirm = false
    @State private var navigationHistory = ["colors"]
    @State private var navigationIndex = 0
    @State private var navigating = false
    private let onApplied: ((Double?) -> Void)?
    private let embedded: Bool
    private let usesExternalSelection: Bool
    private let hostSections: [ConfigHostSettingsSection]

    private var selection: String {
        get { usesExternalSelection ? selectionBinding : localSelection }
        nonmutating set {
            if usesExternalSelection { selectionBinding = newValue } else { localSelection = newValue }
        }
    }

    private var isHostSection: Bool { hostSections.contains { $0.id == selection } && search.isEmpty }
    private var navigation: [ConfigPanel] { ConfigCatalog.shared.rayonNavigation }

    public init(
        embedded: Bool = false,
        hostSections: [ConfigHostSettingsSection] = [],
        selection: Binding<String>? = nil,
        onApplied: ((Double?) -> Void)? = nil
    ) {
        self.hostSections = hostSections
        let initialSelection = selection?.wrappedValue ?? hostSections.first?.id ?? "colors"
        _localSelection = State(initialValue: initialSelection)
        _selectionBinding = selection ?? .constant(initialSelection)
        usesExternalSelection = selection != nil
        _navigationHistory = State(initialValue: [initialSelection])
        self.embedded = embedded
        self.onApplied = onApplied
        _showPreview = State(initialValue: !embedded)
    }

    private var panel: ConfigPanel? { navigation.first { $0.id == selection } }

    public var body: some View {
        HStack(spacing: 0) {
            categoryColumn
                .frame(width: 200)
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: RX.Space.s4) {
                    content
                        .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                    if showPreview && !isHostSection && search.isEmpty {
                        ScrollView {
                            ConfigPreview(model: model)
                                .rxCard(padding: 0)
                                .padding(.bottom, RX.Space.s6)
                        }
                        .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
                        .padding(.trailing, RX.Space.s6)
                        .padding(.top, RX.Space.s3)
                    }
                }
                if !isHostSection || model.isDirty {
                    applyBar
                }
            }
        }
        .background(RXWindowBackground().ignoresSafeArea())
        .toolbarBackground(.hidden, for: .windowToolbar)
        .modifier(ConfigToolbar(leading: {
            ControlGroup {
                    Button { navigate(-1) } label: { Label("Back", systemImage: "chevron.left") }
                        .disabled(navigationIndex == 0)
                    Button { navigate(1) } label: { Label("Forward", systemImage: "chevron.right") }
                        .disabled(navigationIndex + 1 >= navigationHistory.count)
            }
        }, trailing: {
            Group {
                if !isHostSection {
                    ControlGroup {
                        Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                            .disabled(model.undoStack.isEmpty)
                        Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                            .disabled(model.redoStack.isEmpty)
                    }
                    .help("Undo or redo a terminal setting change")
                    Button { resetConfirm = true } label: { Label("Reset All", systemImage: "arrow.counterclockwise") }
                        .help("Reset every terminal setting to its default")
                    Button { showPreview.toggle() } label: { Label(showPreview ? "Hide Preview" : "Show Preview", systemImage: "sidebar.right") }
                        .help(showPreview ? "Hide Preview" : "Show Preview")
                }
            }
        }))
        .searchable(text: $search, placement: .toolbar, prompt: "Search settings")
        .onChange(of: selection) { next in
            if navigating { navigating = false; return }
            navigationHistory = Array(navigationHistory.prefix(navigationIndex + 1)) + [next]
            navigationIndex = navigationHistory.count - 1
        }
        .confirmationDialog("Reset every terminal setting to its default?", isPresented: $resetConfirm) {
            Button("Reset All", role: .destructive) { model.edit { $0 = ConfigDocument() } }
        }
        .frame(minWidth: embedded ? 700 : 960, minHeight: 560)
    }

    // MARK: Category column

    private var categoryColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                if !hostSections.isEmpty {
                    categorySection("Rayon")
                    ForEach(hostSections) { section in
                        categoryRow(section.title, icon: section.icon, id: section.id)
                    }
                }
                categorySection("Terminal")
                ForEach(navigation) { panel in
                    categoryRow(panel.name, icon: icon(panel.id), id: panel.id)
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

    private func categoryRow(_ title: String, icon: String, id: String) -> some View {
        let selected = selection == id && search.isEmpty
        return Button {
            search = ""
            selection = id
        } label: {
            HStack(spacing: RX.Space.s2) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.rxAccent : Color.rxInkSecondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .foregroundStyle(.rxInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let count = modifiedCount(id), count > 0 {
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

    private func modifiedCount(_ panelID: String) -> Int? {
        guard let panel = navigation.first(where: { $0.id == panelID }) else { return nil }
        let keys = Set(panel.settingIDs.compactMap { ConfigCatalog.shared.registry[$0]?.key })
        return model.document.overrides.keys.filter { keys.contains($0) }.count
    }

    // MARK: Apply bar

    private var applyBar: some View {
        VStack(alignment: .leading, spacing: RX.Space.s2) {
            HStack(spacing: RX.Space.s2) {
                StatusDot(model.isDirty ? .warning : .success)
                Text(model.isDirty ? "Unsaved terminal changes" : "Terminal settings applied")
                    .font(.rxBody)
                    .foregroundStyle(.rxInk)
                Spacer()
                Button("Discard") { model.discard() }
                    .rxGlassAction()
                    .disabled(!model.isDirty)
                Button("Apply") {
                    let fontChanged = model.document.overrides["font-size"] != model.saved.overrides["font-size"]
                    if model.save(), fontChanged { onApplied?(model.document.overrides["font-size"]?.first.flatMap(Double.init) ?? 14) }
                }
                .rxPrimaryAction()
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.isDirty)
            }
            if !model.message.isEmpty {
                HStack(spacing: RX.Space.s2) {
                    HelpText(model.message)
                        .textSelection(.enabled)
                    Spacer()
                    Button { model.message = "" } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Dismiss")
                }
            }
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: RX.Space.s6) {
                    PageTitle("Search Results", subtitle: searchSubtitle)
                    ForEach(hostSearchResults) { section in
                        section.content
                    }
                    ForEach(navigation) { category in
                        let matches = searchResults.filter { setting in category.settingIDs.contains { ConfigCatalog.shared.registry[$0]?.key == setting.key } }
                        if !matches.isEmpty {
                            VStack(alignment: .leading, spacing: RX.Space.s2) {
                                HStack {
                                    CapsLabel(category.name)
                                    Spacer()
                                    Button("Show in \(category.name)") {
                                        jumpTarget = matches.first?.key
                                        selection = category.id
                                        search = ""
                                    }
                                    .buttonStyle(.link)
                                    .font(.rxHelp)
                                }
                                .padding(.leading, RX.Space.s4)
                                RXDividedStack {
                                    ForEach(matches) { setting in
                                        ConfigSettingRow(model: model, setting: setting, query: search)
                                    }
                                }
                                .padding(.horizontal, RX.Space.s4)
                                .background(Color.clear.rxCard(padding: 0))
                            }
                        }
                    }
                    if searchResults.isEmpty && hostSearchResults.isEmpty {
                        EmptyStateView("No settings match “\(search)”", systemImage: "magnifyingglass", message: "Try another word, or a setting's key such as font-size.")
                            .rxCard()
                    }
                }
                .padding(.horizontal, RX.Space.s6)
                .padding(.top, RX.Space.s3)
                .padding(.bottom, RX.Space.s6)
            }
        } else if let section = hostSections.first(where: { $0.id == selection }) {
            ScrollView {
                VStack(alignment: .leading, spacing: RX.Space.s6) {
                    PageTitle(section.title, subtitle: section.subtitle)
                    section.content
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, RX.Space.s6)
                .padding(.top, RX.Space.s3)
                .padding(.bottom, RX.Space.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if selection == "keybinds" {
            ScrollView {
                VStack(alignment: .leading, spacing: RX.Space.s6) {
                    PageTitle("Keybindings", subtitle: "Shortcuts and the terminal actions they run.")
                    ConfigKeybindingList(model: model)
                }
                .padding(.horizontal, RX.Space.s6)
                .padding(.top, RX.Space.s3)
                .padding(.bottom, RX.Space.s6)
            }
        } else if let panel {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: RX.Space.s6) {
                        PageTitle(panel.name, subtitle: panel.note.map(stripTags))
                        ForEach(panel.groups ?? []) { group in
                            VStack(alignment: .leading, spacing: RX.Space.s2) {
                                if !group.name.isEmpty {
                                    CapsLabel(group.name)
                                        .padding(.leading, RX.Space.s4)
                                }
                                RXDividedStack {
                                    ForEach(group.settings, id: \.self) { id in
                                        if let setting = ConfigCatalog.shared.registry[id] {
                                            ConfigSettingRow(model: model, setting: setting).id(setting.key)
                                        }
                                    }
                                }
                                .padding(.horizontal, RX.Space.s4)
                                .background(Color.clear.rxCard(padding: 0))
                            }
                        }
                    }
                    .padding(.horizontal, RX.Space.s6)
                    .padding(.top, RX.Space.s3)
                    .padding(.bottom, RX.Space.s6)
                }
                .id(panel.id)
                .task(id: jumpTarget) {
                    guard let jumpTarget else { return }
                    await Task.yield()
                    proxy.scrollTo(jumpTarget, anchor: .top)
                }
            }
        } else {
            EmptyStateView("Choose a category", systemImage: "slider.horizontal.3", message: "Pick a category on the left.")
                .frame(maxHeight: .infinity)
                .onAppear { if hostSections.isEmpty { selection = navigation.first?.id ?? "colors" } }
        }
    }

    private var searchSubtitle: String {
        let count = searchResults.count + hostSearchResults.count
        return count == 0 ? "Nothing found" : "\(count) match\(count == 1 ? "" : "es") for “\(search)”"
    }

    private func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private var hostSearchResults: [ConfigHostSettingsSection] {
        let tokens = search.lowercased().split(whereSeparator: \.isWhitespace)
        return hostSections.filter { section in
            let text = "\(section.title) \(section.keywords)".lowercased()
            return tokens.allSatisfy { text.contains($0) }
        }
    }

    private var searchResults: [ConfigSetting] {
        let tokens = search.lowercased().split(whereSeparator: \.isWhitespace)
        return ConfigCatalog.shared.rayonSettings.filter { setting in
            let category = navigation.first { panel in panel.settingIDs.contains { ConfigCatalog.shared.registry[$0]?.key == setting.key } }
            let group = category?.groups?.first { $0.settings.contains { ConfigCatalog.shared.registry[$0]?.key == setting.key } }
            let haystack = [setting.key, setting.name, setting.description, category?.name ?? "", group?.name ?? ""].joined(separator: " ").lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    private func navigate(_ delta: Int) {
        let next = navigationIndex + delta
        guard navigationHistory.indices.contains(next) else { return }
        navigating = true; navigationIndex = next; selection = navigationHistory[next]
    }

    private func icon(_ id: String) -> String {
        ["application": "app", "terminal": "terminal", "clipboard": "doc.on.clipboard", "window": "rectangle.inset.filled", "colors": "paintpalette", "fonts": "textformat", "keybinds": "keyboard", "mouse": "computermouse"][id] ?? "slider.horizontal.3"
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
