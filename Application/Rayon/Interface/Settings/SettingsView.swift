//
//  SettingsView.swift
//  Rayon
//
//  Settings: Rayon's pages and the terminal's categories in one list, the
//  chosen one as a form, and search across both. On the Mac it is the
//  Settings window: a sidebar and the page, on the window's material; on the
//  iPhone and iPad a list that pushes each page.
//

import RayonDesign
import RayonModule
import RayonTerminal
import SwiftUI

struct SettingsView: View {
    #if os(macOS)
        @ObservedObject private var navigation = AppRouter.shared.settingsNavigation
    #endif
    @Environment(\.undoManager) private var undoManager
    @State private var search = ""
    #if os(iOS)
        /// A page opened from search.
        @State private var shown: SettingsPage?
    #endif

    var body: some View {
        content
            .terminalSettingsChrome()
            .onAppear {
                // Changes go on the window's undo stack, where ⌘Z, Edit ›
                // Undo and shaking the device find them.
                TerminalSettings.shared.useUndoManager(undoManager)
                #if DEBUG
                    if let text = ProcessInfo.processInfo.environment["RAYON_PREVIEW_SEARCH"] {
                        search = text
                    }
                    #if os(iOS)
                        if let id = ProcessInfo.processInfo.environment["RAYON_PREVIEW_SETTINGS"], shown == nil {
                            shown = SettingsPage(id: id)
                        }
                    #endif
                #endif
            }
            .onChange(of: undoManager) { TerminalSettings.shared.useUndoManager(undoManager) }
    }

    #if os(macOS)
        private var selected: SettingsPage {
            SettingsPage(id: navigation.selection) ?? .general
        }

        private var content: some View {
            NavigationSplitView {
                List(selection: Binding(get: { search.isEmpty ? selected.sidebarPage.id : nil }, set: { id in
                    guard let id else { return }
                    search = ""
                    navigation.go(id)
                })) {
                    ForEach(SettingsPage.sections) { section in
                        Section {
                            ForEach(section.pages, id: \.self) { page in
                                SettingsPageLabel(page: page).tag(page.id)
                            }
                        } header: {
                            if let title = section.title { Text(title) }
                        }
                    }
                }
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 280)
            } detail: {
                ZStack {
                    RXWindowBackground()
                        .ignoresSafeArea()
                    Group {
                        if search.isEmpty {
                            // A new page starts at its top; its rows are all new anyway.
                            SettingsPageView(page: selected) { navigation.go($0.id) }
                                .id(selected)
                        } else {
                            SettingsSearchResults(query: search) { id in
                                search = ""
                                navigation.go(id)
                            }
                        }
                    }
                    // Outside the page's identity, so its terminal outlives page switches.
                    .terminalPreview(isShown: search.isEmpty && selected.previews)
                }
                .navigationTitle(search.isEmpty ? selected.title : String(localized: "Search"))
                .rxClearToolbar()
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button { navigation.step(-1) } label: { Label("Back", systemImage: "chevron.left") }
                            .disabled(!navigation.canGoBack)
                            .help("Show the previous page")
                        Button { navigation.step(1) } label: { Label("Forward", systemImage: "chevron.right") }
                            .disabled(!navigation.canGoForward)
                            .help("Show the next page")
                    }
                }
            }
            .searchable(text: $search, placement: .toolbar, prompt: "Search settings")
            .frame(minWidth: 720, minHeight: 480)
        }
    #else
        private var content: some View {
            Group {
                if search.isEmpty {
                    List {
                        ForEach(SettingsPage.sections) { section in
                            Section {
                                ForEach(section.pages, id: \.self) { page in
                                    NavigationLink(value: page) {
                                        SettingsPageLabel(page: page)
                                    }
                                }
                            } header: {
                                if let title = section.title { Text(title) }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(RXBackdrop().ignoresSafeArea())
                } else {
                    SettingsSearchResults(query: search) { id in
                        search = ""
                        shown = SettingsPage(id: id)
                    }
                }
            }
            .navigationDestination(for: SettingsPage.self) { destination($0) }
            .navigationDestination(for: TerminalSettingsSubpage.self) { destination(.terminalSubpage($0)) }
            .navigationDestination(item: $shown) { destination($0) }
            .searchable(text: $search, prompt: "Search settings")
            .navigationTitle("Settings")
        }

        private func destination(_ page: SettingsPage) -> some View {
            SettingsPageView(page: page) { _ in }
                .terminalPreview(isShown: page.previews)
                .navigationTitle(page.title)
                // A large title has no scroll view to collapse into above the preview.
                .navigationBarTitleDisplayMode(page.previews ? .inline : .automatic)
        }
    #endif
}

private struct SettingsPageLabel: View {
    let page: SettingsPage

    var body: some View {
        if case let .terminal(category) = page {
            Label(page.title, systemImage: page.icon)
                .badge(category.changedCount)
        } else {
            Label(page.title, systemImage: page.icon)
        }
    }
}

/// A page: Rayon's groups, then on a terminal page its settings. `open`
/// shows a terminal subpage on the Mac.
private struct SettingsPageView: View {
    let page: SettingsPage
    let open: (TerminalSettingsSubpage) -> Void

    var body: some View {
        switch page {
        case let .terminal(category):
            TerminalSettingsPage(category, open: open) {
                ForEach(page.groups) { SettingsGroupSection(group: $0) }
            }
        case let .terminalSubpage(subpage):
            TerminalSettingsPage(subpage.category, subpage: subpage, open: open)
        default:
            Form {
                ForEach(page.groups) { SettingsGroupSection(group: $0) }
            }
            .settingsForm()
        }
    }
}

/// Rayon's groups and the terminal's settings matching every word typed.
/// They are worked out once per query, and a moment after typing stops
/// rather than on every keystroke.
private struct SettingsSearchResults: View {
    let query: String
    let show: (String) -> Void
    @State private var found: Found?

    private struct Found {
        let query: String
        let groups: [SettingsGroup]
        let terminal: TerminalSettingsSearch

        @MainActor init(_ query: String) {
            self.query = query
            groups = SettingsGroup.allCases.filter { $0.isAvailable && $0.matches(query) }
            terminal = TerminalSettingsSearch(query)
        }
    }

    var body: some View {
        Group {
            if let found {
                if found.groups.isEmpty, found.terminal.isEmpty {
                    ContentUnavailableView.search(text: found.query)
                } else {
                    Form {
                        ForEach(found.groups) { group in
                            Section {
                                Button("Show \(group.page.title)", systemImage: group.page.icon) { show(group.page.id) }
                            }
                            SettingsGroupSection(group: group, prefix: group.page.title)
                        }
                        TerminalSettingsSearchSections(found.terminal, show: show)
                    }
                    .settingsForm()
                }
            }
        }
        .task(id: query) {
            // The first query shows at once; later ones wait for a pause.
            if found != nil {
                try? await Task.sleep(for: .milliseconds(150))
                if Task.isCancelled { return }
            }
            found = Found(query)
        }
    }
}
