//
//  SnippetsView.swift
//  Rayon
//
//  Snippet cards with their SF Symbol, group, comment and command, a
//  group filter, and Run… (the server picker, then the batch run).
//

import RayonModule
import SwiftUI

struct SnippetsView: View {
    @EnvironmentObject var store: RayonStore
    @State private var searchText = ""
    @State private var groupFilter: String?

    private var groupNames: [String] {
        Set(store.snippets.map(\.group)).filter { !$0.isEmpty }.sorted()
    }

    private var filtered: [RDSnippet] {
        store.snippets
            .filter { groupFilter == nil || $0.group == groupFilter }
            .filter { searchText.isEmpty || $0.isQualifiedForSearch(text: searchText) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        content
            .onChange(of: groupNames) { _, names in
                if let groupFilter, !names.contains(groupFilter) { self.groupFilter = nil }
            }
    }

    @ViewBuilder private var cards: some View {
        if store.snippets.isEmpty {
            EmptyStateView(
                "No snippets yet",
                systemImage: "chevron.left.forwardslash.chevron.right",
                actionTitle: "New Snippet"
            ) {
                SnippetActions.edit(nil)
            }
            .rxCard()
        } else if filtered.isEmpty {
            EmptyStateView("No matches", systemImage: "magnifyingglass")
                .rxCard()
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280), spacing: RX.Space.s4, alignment: .top)],
                alignment: .leading,
                spacing: RX.Space.s4
            ) {
                ForEach(filtered) { snippet in
                    SnippetTile(snippet: snippet)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .animation(.rxMove, value: filtered.map(\.id))
        }
    }

    private var groupPicker: some View {
        Picker("Group", selection: $groupFilter) {
            Text("All Groups").tag(String?.none)
            Divider()
            ForEach(groupNames, id: \.self) { Text($0).tag(String?.some($0)) }
        }
        .help("Filter by group")
    }

    #if os(macOS)
        private var content: some View {
            PageScaffold(
                search: $searchText,
                searchPrompt: "Search snippets",
                primary: ToolbarAction("New Snippet", systemImage: "plus", primary: true) { SnippetActions.edit(nil) }
            ) {
                if !groupNames.isEmpty { groupPicker }
            } trailing: {
            } header: {
                PageTitle("Snippets")
            } content: {
                cards
            }
        }
    #else
        private var content: some View {
            ScrollView {
                cards.padding(RX.Space.s4)
            }
            .background(RXBackdrop().ignoresSafeArea())
            .searchable(text: $searchText, prompt: "Search snippets")
            .navigationTitle("Snippets")
            .toolbar {
                ToolbarItemGroup {
                    if !groupNames.isEmpty {
                        Menu {
                            groupPicker
                        } label: {
                            Label("Filter by Group", systemImage: groupFilter == nil
                                ? "line.3.horizontal.decrease.circle"
                                : "line.3.horizontal.decrease.circle.fill")
                        }
                    }
                    Button("New Snippet", systemImage: "plus") { SnippetActions.edit(nil) }
                }
            }
        }
    #endif
}

/// A snippet's card: its symbol, name, group and comment, the start of its
/// command, Run… and its menu. A double click (a tap on iPhone and iPad)
/// edits it.
private struct SnippetTile: View {
    let snippet: RDSnippet
    @State private var hovered = false

    private var detail: String {
        [snippet.group, snippet.comment].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s3) {
            HStack(alignment: .top, spacing: RX.Space.s3) {
                SymbolTile(snippet.displaySymbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snippet.name.isEmpty ? "Untitled" : "\(snippet.name)")
                        .font(.rxBodyStrong)
                        .foregroundStyle(.rxInk)
                        .lineLimit(1)
                    if !detail.isEmpty {
                        HelpText(verbatim: detail)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: RX.Space.s2)
                #if os(macOS)
                    Button("Run…") { SnippetActions.run(snippet.id) }
                        .buttonStyle(.rx(size: .small))
                #endif
                Menu {
                    SnippetMenuItems(snippet: snippet)
                } label: {
                    Label("Actions", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 28, minHeight: 28)
                }
                #if os(macOS)
                .moreMenu()
                #endif
            }
            CodeBlock(snippet.code.trimmingCharacters(in: .whitespacesAndNewlines), lineLimit: 4)
        }
        .rxCard()
        .scaleEffect(hovered ? 1.01 : 1)
        .animation(.easeOut(duration: 0.15), value: hovered)
        .contentShape(RoundedRectangle(cornerRadius: RX.Radius.card, style: .continuous))
        .onHover { hovered = $0 }
        #if os(macOS)
            .onTapGesture(count: 2) { SnippetActions.edit(snippet.id) }
        #else
            .onTapGesture { SnippetActions.edit(snippet.id) }
        #endif
            .contextMenu { SnippetMenuItems(snippet: snippet) }
    }
}
