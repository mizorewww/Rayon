//
//  SettingsView.swift
//  Rayon
//
//  Settings: Rayon's pages and the terminal's categories in one list, the
//  chosen one as a form, and search across both. On the Mac it is a sidebar
//  destination with its own list beside the page; on the iPhone and iPad a
//  list that pushes each page.
//

import RayonModule
import RayonTerminal
import SwiftUI

struct SettingsView: View {
    #if os(macOS)
        @ObservedObject private var navigation = AppRouter.shared.settingsNavigation
    #endif
    /// False while the window shows another page: Settings then adds
    /// nothing to its toolbar.
    var active = true
    @State private var search = ""
    @State private var showsPreview = true
    @State private var confirmingReset = false
    #if os(iOS)
        /// A page opened from search.
        @State private var shown: SettingsPage?
    #endif

    var body: some View {
        content
            .terminalSettingsChrome(confirmingReset: $confirmingReset)
            .onAppear {
                #if DEBUG
                    if let text = ProcessInfo.processInfo.environment["RAYON_PREVIEW_SEARCH"] {
                        search = text
                    }
                #endif
            }
    }

    #if os(macOS)
        private var selected: SettingsPage {
            SettingsPage(id: navigation.selection) ?? .general
        }

        private var content: some View {
            HStack(spacing: 0) {
                List(selection: Binding(get: { search.isEmpty ? navigation.selection : nil }, set: { id in
                    guard let id else { return }
                    search = ""
                    navigation.go(id)
                })) {
                    ForEach(SettingsPage.sections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.pages, id: \.self) { page in
                                SettingsPageLabel(page: page).tag(page.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 200)
                Divider()
                Group {
                    if search.isEmpty {
                        SettingsPageView(page: selected, showsPreview: $showsPreview)
                            .id(selected)
                    } else {
                        SettingsSearchResults(query: search) { id in
                            search = ""
                            navigation.go(id)
                        }
                    }
                }
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
                    ToolbarItemGroup(placement: .primaryAction) { tools(for: search.isEmpty ? selected : nil) }
                }
            }
            .modifier(ToolbarSearch(text: $search, active: active))
            .onChange(of: active) {
                _, now in if !now {
                    search = ""
                }
            }
            .frame(minWidth: 700, minHeight: 560)
        }
    #else
        private var content: some View {
            Group {
                if search.isEmpty {
                    List {
                        ForEach(SettingsPage.sections, id: \.title) { section in
                            Section(section.title) {
                                ForEach(section.pages, id: \.self) { page in
                                    NavigationLink {
                                        destination(page)
                                    } label: {
                                        SettingsPageLabel(page: page)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    SettingsSearchResults(query: search) { id in
                        search = ""
                        shown = SettingsPage(id: id)
                    }
                }
            }
            .navigationDestination(item: $shown) { destination($0) }
            .searchable(text: $search, prompt: "Search settings")
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .primaryAction) { moreMenu(for: nil) } }
        }

        private func destination(_ page: SettingsPage) -> some View {
            SettingsPageView(page: page, showsPreview: $showsPreview)
                .navigationTitle(page.title)
                .toolbar { ToolbarItem(placement: .primaryAction) { moreMenu(for: page) } }
        }

        private func moreMenu(for page: SettingsPage?) -> some View {
            Menu {
                tools(for: page)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    #endif

    /// The terminal's tools; Reset only where terminal settings show.
    private func tools(for page: SettingsPage?) -> some View {
        let terminal: TerminalSettingsCategory? = if case let .terminal(category) = page {
            category
        } else {
            nil
        }
        return TerminalSettingsTools(
            showsPreview: $showsPreview,
            confirmingReset: $confirmingReset,
            previewAvailable: terminal?.previews ?? false,
            resetAvailable: terminal != nil || page == nil
        )
    }
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

/// A page: Rayon's groups, then on a terminal page its settings.
private struct SettingsPageView: View {
    let page: SettingsPage
    @Binding var showsPreview: Bool

    var body: some View {
        if case let .terminal(category) = page {
            TerminalSettingsPage(category, showsPreview: $showsPreview) {
                ForEach(page.groups) { SettingsGroupSection(group: $0) }
            }
        } else {
            Form {
                ForEach(page.groups) { SettingsGroupSection(group: $0) }
            }
            .formStyle(.grouped)
        }
    }
}

/// Rayon's groups and the terminal's settings matching every word typed.
private struct SettingsSearchResults: View {
    let query: String
    let show: (String) -> Void

    var body: some View {
        let groups = SettingsGroup.allCases.filter { $0.isAvailable && $0.matches(query) }
        if groups.isEmpty, !TerminalSettingsSearchSections.matches(query) {
            ContentUnavailableView.search(text: query)
        } else {
            Form {
                ForEach(groups) { group in
                    Section {
                        Button("Show \(group.page.title)", systemImage: group.page.icon) { show(group.page.id) }
                    }
                    SettingsGroupSection(group: group, prefix: group.page.title)
                }
                TerminalSettingsSearchSections(query: query, show: show)
            }
            .formStyle(.grouped)
        }
    }
}

#if os(macOS)
    private struct ToolbarSearch: ViewModifier {
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
