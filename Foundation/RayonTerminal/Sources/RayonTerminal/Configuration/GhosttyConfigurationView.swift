import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// App-owned preferences share the editor's navigation without coupling this package to RayonStore.
public struct ConfigHostSettingsSection: Identifiable {
    public let id: String
    let title: String
    let icon: String
    let keywords: String
    let content: AnyView

    @MainActor public init<Content: View>(id: String, title: String, icon: String, keywords: String,
                                        @ViewBuilder content: () -> Content) {
        self.id = id
        self.title = title
        self.icon = icon
        self.keywords = keywords
        self.content = AnyView(content())
    }
}

/// Full native configuration editor, backed by the pinned Ghostty Config schema.
public struct GhosttyConfigurationView: View {
    @StateObject private var model = ConfigEditorModel.shared
    @State private var selection: String? = "colors"
    @State private var search = ""
    @State private var jumpTarget: String?
    @State private var showPreview = true
    @State private var importing = false
    @State private var exporting = false
    @State private var importSheet = false
    @State private var importText = ""
    @State private var importError = ""
    @State private var shareSheet = false
    @State private var resetConfirm = false
    @State private var navigationHistory = ["colors"]
    @State private var navigationIndex = 0
    @State private var navigating = false
    private let onApplied: ((Double?) -> Void)?
    private let embedded: Bool
    private let hostSections: [ConfigHostSettingsSection]
    private var isHostSection: Bool { hostSections.contains { $0.id == selection } && search.isEmpty }
    public init(embedded: Bool = false, hostSections: [ConfigHostSettingsSection] = [], onApplied: ((Double?) -> Void)? = nil) {
        self.hostSections = hostSections
        let initialSelection = hostSections.first?.id ?? "colors"
        _selection = State(initialValue: initialSelection)
        _navigationHistory = State(initialValue: [initialSelection])
        self.embedded = embedded
        self.onApplied = onApplied
        _showPreview = State(initialValue: !embedded)
    }
    private var panel: ConfigPanel? { ConfigCatalog.shared.navigation.first { $0.id == selection } }
    public var body: some View {
        ConfigEditorLayout(embedded: embedded) {
            List(selection: $selection) {
                if !hostSections.isEmpty {
                    Section("Rayon") {
                        ForEach(hostSections) { section in
                            Label(section.title, systemImage: section.icon).tag(section.id)
                        }
                    }
                }
                Section(hostSections.isEmpty ? "Configuration" : "Terminal") {
                    ForEach(ConfigCatalog.shared.navigation) { panel in
                        Label(panel.name, systemImage: icon(panel.id)).tag(panel.id)
                    }
                }
                Section("Tools") {
                    Label("Font Playground", systemImage: "textformat").tag("playground")
                    Label("Import & Export", systemImage: "arrow.up.arrow.down.doc").tag("transfer")
                    Label("Custom Settings", systemImage: "curlybraces").tag("custom")
                }
                Section {
                    Link("Ghostty Config on GitHub", destination: URL(string: "https://github.com/zerebos/ghostty-config")!)
                    Text("200 settings · 633 themes").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationSplitViewColumnWidth(min: 175, ideal: 205, max: 260)
        } detail: {
            VStack(spacing: 0) {
                HSplitView {
                    content.frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                    if showPreview && !isHostSection { ConfigPreview(model: model).frame(minWidth: 320, idealWidth: 370, maxWidth: 480) }
                }
                if !isHostSection || model.isDirty {
                    Divider()
                    HStack {
                        Circle().fill(model.isDirty ? Color.orange : .green).frame(width: 6, height: 6)
                        Text(model.isDirty ? "Unsaved terminal changes" : "Terminal settings saved").font(.caption)
                        Text("· \(model.document.overrides.count) overrides").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Discard Terminal Changes") { model.discard() }.disabled(!model.isDirty)
                        Button("Apply Terminal Changes") {
                            let fontChanged = model.document.overrides["font-size"] != model.saved.overrides["font-size"]
                            if model.save(), fontChanged { onApplied?(model.document.overrides["font-size"]?.first.flatMap(Double.init) ?? 14) }
                        }
                            .keyboardShortcut("s", modifiers: .command).buttonStyle(.borderedProminent)
                    }.padding(12)
                    if !model.message.isEmpty {
                        HStack { Text(model.message).font(.caption).textSelection(.enabled); Spacer(); Button { model.message = "" } label: { Image(systemName: "xmark") }.buttonStyle(.borderless) }
                            .padding(10).background(Color.accentColor.opacity(0.08))
                    }
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle(hostSections.isEmpty ? "Terminal Configuration" : "Settings")
        .searchable(text: $search, prompt: "Search settings and documentation")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { navigate(-1) } label: { Image(systemName: "chevron.left") }.disabled(navigationIndex == 0).help("Back")
                Button { navigate(1) } label: { Image(systemName: "chevron.right") }.disabled(navigationIndex + 1 >= navigationHistory.count).help("Forward")
            }
            ToolbarItemGroup {
                if !isHostSection {
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(model.undoStack.isEmpty).help("Undo configuration edit")
                    Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(model.redoStack.isEmpty).help("Redo configuration edit")
                    Button { importText = ""; importSheet = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    Button { exporting = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    Button { shareSheet = true } label: { Label("Share", systemImage: "link") }
                    Button { showPreview.toggle() } label: { Label("Preview", systemImage: "sidebar.right") }
                }
            }
        }
        .onChange(of: selection) { next in
            guard let next else { return }
            if navigating { navigating = false; return }
            navigationHistory = Array(navigationHistory.prefix(navigationIndex + 1)) + [next]
            navigationIndex = navigationHistory.count - 1
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .data]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                importText = try String(contentsOf: url, encoding: .utf8)
                importError = ""; importSheet = true
            } catch { model.message = error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: ConfigTextFile(text: model.document.serialized()), contentType: .plainText, defaultFilename: "ghostty-config") { result in
            if case let .failure(error) = result { model.message = error.localizedDescription }
        }
        .sheet(isPresented: $importSheet) { importView }
        .sheet(isPresented: $shareSheet) { ConfigShareView(model: model) }
        .confirmationDialog("Reset every setting to its default?", isPresented: $resetConfirm) { Button("Reset All", role: .destructive) { model.edit { $0 = ConfigDocument() } } }
        .frame(minWidth: embedded ? 740 : 960, minHeight: 650)
    }
    @ViewBuilder private var content: some View {
        if !search.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("Search Results").font(.largeTitle.bold())
                    ForEach(hostSearchResults) { section in
                        section.content
                        Text("Changes apply immediately.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(ConfigCatalog.shared.navigation) { category in
                        let matches = searchResults.filter { setting in category.settingIDs.contains { ConfigCatalog.shared.registry[$0]?.key == setting.key } }
                        if !matches.isEmpty {
                            Text(category.name).font(.title3.bold()).padding(.top, 12)
                            ForEach(matches) { setting in
                                VStack(alignment: .leading) {
                                    Button("Show in \(category.name)") { jumpTarget = setting.key; selection = category.id; search = "" }.buttonStyle(.link)
                                    ConfigSettingRow(model: model, setting: setting, query: search)
                                }
                            }
                        }
                    }
                    if searchResults.isEmpty && hostSearchResults.isEmpty { Text("No settings match “\(search)”").foregroundStyle(.secondary) }
                }.padding(24)
            }
        } else if let section = hostSections.first(where: { $0.id == selection }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section.content
                    Text("Changes apply immediately.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
        } else if selection == "playground" { ConfigFontPlayground() }
        else if selection == "transfer" { transferView }
        else if selection == "custom" { ConfigCustomSettings(model: model) }
        else if selection == "keybinds" {
            ScrollView { VStack(alignment: .leading, spacing: 16) { Text("Keybindings").font(.largeTitle.bold()); ConfigKeybindingList(model: model) }.padding(24) }
        } else if let panel {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text(panel.name).font(.largeTitle.bold())
                    if let note = panel.note { Text(note).foregroundStyle(.secondary) }
                    ForEach(panel.groups ?? []) { group in
                        if !group.name.isEmpty { Text(group.name).font(.title3.weight(.semibold)).padding(.top, 14) }
                        if let note = group.note { Text(note.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)).font(.caption).foregroundStyle(.secondary) }
                        ForEach(group.settings, id: \.self) { id in
                            if let setting = ConfigCatalog.shared.registry[id] { ConfigSettingRow(model: model, setting: setting).id(setting.key) }
                        }
                    }
                }.padding(24)
            }.id(panel.id)
                .task(id: jumpTarget) {
                    guard let jumpTarget else { return }
                    await Task.yield()
                    proxy.scrollTo(jumpTarget, anchor: .top)
                }
            }
        }
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
        return ConfigCatalog.shared.settings.filter { setting in
            let category = ConfigCatalog.shared.navigation.first { panel in panel.settingIDs.contains { ConfigCatalog.shared.registry[$0]?.key == setting.key } }
            let group = category?.groups?.first { $0.settings.contains { ConfigCatalog.shared.registry[$0]?.key == setting.key } }
            let haystack = [setting.key, setting.name, setting.description, setting.note ?? "", category?.name ?? "", group?.name ?? "", group?.note ?? ""].joined(separator: " ").lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }
    private var transferView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import & Export").font(.largeTitle.bold())
            Text("Only changes from the Ghostty Config defaults are exported. Import merges into your current draft; palette entries merge by index and keybindings append.").foregroundStyle(.secondary)
            HStack {
                Button("Import file…") { importing = true }
                Button("Paste config or share URL…") { importText = NSPasteboard.general.string(forType: .string) ?? ""; importSheet = true }
                Button("Copy") { copy(model.document.serialized()); model.message = "Configuration copied." }
                Button("Download…") { exporting = true }
            }
            ScrollView([.vertical, .horizontal]) { Text(model.document.serialized()).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            HStack { Button("Share selected settings…") { shareSheet = true }; Spacer(); Button("Reset all…", role: .destructive) { resetConfirm = true } }
        }.padding(24)
    }
    private var importView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Configuration").font(.title2.bold())
            Text("Paste Ghostty configuration or a ghostty.zerebos.com share URL. Review the merged preview before importing.").foregroundStyle(.secondary)
            TextEditor(text: $importText).font(.system(.body, design: .monospaced)).frame(height: 200)
            HStack {
                Button("Choose file…") { importSheet = false; importing = true }
                Button("Preview merge") {
                    do { var result = model.document; try result.merge(importText); importError = result.serialized() }
                    catch { importError = error.localizedDescription }
                }
            }
            if !importError.isEmpty { ScrollView { Text(importError).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 150) }
            HStack {
                Spacer(); Button("Cancel") { importSheet = false }.keyboardShortcut(.cancelAction)
                Button("Merge into draft") { do { try model.importConfig(importText); importSheet = false; model.message = "Imported into draft. Save & Apply when ready." } catch { importError = error.localizedDescription } }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 680)
    }
    private func navigate(_ delta: Int) {
        let next = navigationIndex + delta
        guard navigationHistory.indices.contains(next) else { return }
        navigating = true; navigationIndex = next; selection = navigationHistory[next]
    }
    private func icon(_ id: String) -> String {
        ["application": "app", "terminal": "terminal", "clipboard": "doc.on.clipboard", "window": "macwindow", "colors": "paintpalette", "fonts": "textformat", "keybinds": "keyboard", "mouse": "computermouse", "gtk": "square.grid.2x2", "linux": "desktopcomputer", "macos": "apple.logo"][id] ?? "slider.horizontal.3"
    }
}

struct ConfigTextFile: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else { throw ConfigError.message("Expected a UTF-8 text file") }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
@MainActor private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }

struct ConfigShareView: View {
    @ObservedObject var model: ConfigEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Share Configuration").font(.title2.bold())
            Text("Choose the overrides to include. Links are compatible with Ghostty Config on the web.").foregroundStyle(.secondary)
            HStack { Button("Select all") { selected = Set(model.document.overrides.keys) }; Button("Clear selection") { selected = [] } }
            List(model.document.overrides.keys.sorted(), id: \.self, selection: $selected) { key in Text(key).tag(key) }.frame(height: 180)
            let text = model.document.shareURL(only: selected) ?? model.document.serialized(only: selected)
            Text(model.document.shareURL(only: selected) == nil ? "Over 1,800 characters: sharing configuration text instead." : "Ready to share as a URL.").font(.caption)
            ScrollView { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }.frame(height: 100)
            Text(status).font(.caption)
            HStack { Button("Copy") { copy(text); status = "Copied." }; ShareLink(item: text); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 600).onAppear { selected = Set(model.document.overrides.keys) }
    }
}
struct ConfigCustomSettings: View {
    @ObservedObject var model: ConfigEditorModel
    @State private var key = ""
    @State private var value = ""
    @State private var error = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Custom Settings").font(.largeTitle.bold())
                Text("Preserve new Ghostty keys that are not in this catalog. Custom settings are exported; only supported keys are applied to Rayon.").foregroundStyle(.secondary)
                HStack { TextField("setting-name", text: $key); TextField("value", text: $value); Button("Add") {
                    do { try model.importConfig("\(key) = \(value)"); key = ""; value = ""; error = "" } catch { self.error = error.localizedDescription }
                } }
                Text(error).foregroundStyle(.red)
                ForEach(model.document.overrides.keys.filter { ConfigCatalog.shared.setting(key: $0) == nil }.sorted(), id: \.self) { key in
                    VStack(alignment: .leading) { HStack { Text(key).font(.headline); Spacer(); Button("Remove") { model.reset(key) } }; ConfigRepeatableEditor(model: model, key: key) }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }.padding(24)
        }
    }
}

/// Avoid a nested navigation container inside Rayon's existing main navigation.
private struct ConfigEditorLayout<Sidebar: View, Detail: View>: View {
    let embedded: Bool
    let sidebar: Sidebar
    let detail: Detail
    init(embedded: Bool, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) {
        self.embedded = embedded
        self.sidebar = sidebar()
        self.detail = detail()
    }
    var body: some View {
        if embedded {
            HSplitView {
                sidebar.frame(minWidth: 175, idealWidth: 205, maxWidth: 250)
                detail
            }
        } else {
            NavigationSplitView { sidebar } detail: { detail }
        }
    }
}
