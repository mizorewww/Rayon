//
//  SnippetsView.swift
//  Rayon (macOS)
//
//  Snippet cards with their SF Symbol, group, comment, the command on `terminal-bg`,
//  and Run… (server picker, then the batch run sheet).
//

import RayonModule
import SwiftUI

struct SnippetsView: View {
    @EnvironmentObject var store: RayonStore

    @State private var searchText = ""
    @State private var groupFilter: String = SnippetsView.allGroups
    @State private var creating = false
    @State private var editing: RDSnippet.ID?

    static let allGroups = "\u{0}all"

    var groupNames: [String] {
        Set(store.snippetGroup.snippets.map(\.group)).filter { !$0.isEmpty }.sorted()
    }

    var filtered: [RDSnippet] {
        var result = store.snippetGroup.snippets
        if groupFilter != Self.allGroups {
            result = result.filter { $0.group == groupFilter }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.isQualifiedForSearch(text: searchText) }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        PageScaffold(search: $searchText, searchPrompt: "Search snippets") {
            if !groupNames.isEmpty {
                Picker("Group", selection: $groupFilter) {
                    Text("All Groups").tag(Self.allGroups)
                    Divider()
                    ForEach(groupNames, id: \.self) { Text($0).tag($0) }
                }
                .help("Filter by group")
            }
        } trailing: {
            ToolbarAction("New Snippet", systemImage: "plus", primary: true) { creating = true }
        } header: {
            PageTitle("Snippets", subtitle: "Shell commands you run on one or many servers")
        } content: {
            if store.snippetGroup.snippets.isEmpty {
                EmptyStateView(
                    "No snippets yet",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    message: "Save commands you run often, then run them on several servers at once.",
                    actionTitle: "New Snippet"
                ) {
                    creating = true
                }
                .rxCard()
            } else if filtered.isEmpty {
                EmptyStateView("No matches", systemImage: "magnifyingglass", message: "No snippet matches your search.")
                    .rxCard()
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: RX.Space.s4, alignment: .top)],
                    alignment: .leading,
                    spacing: RX.Space.s4
                ) {
                    ForEach(filtered) { snippet in
                        SnippetTile(snippet: snippet) { editing = snippet.id }
                    }
                }
            }
        }
        .onChange(of: groupNames) { names in
            if groupFilter != Self.allGroups, !names.contains(groupFilter) { groupFilter = Self.allGroups }
        }
        .sheet(isPresented: $creating) {
            SnippetEditorSheet(snippet: nil) { creating = false }
        }
        .sheet(item: Binding(get: { editing.map(EditingID.init) }, set: { editing = $0?.id })) { item in
            SnippetEditorSheet(snippet: item.id) { editing = nil }
        }
    }

    private struct EditingID: Identifiable {
        let id: RDSnippet.ID
    }
}

private struct SnippetTile: View {
    let snippet: RDSnippet
    let edit: () -> Void
    @State private var hovered = false

    var detail: String {
        [snippet.group, snippet.comment].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RX.Space.s3) {
            HStack(alignment: .top, spacing: RX.Space.s3) {
                SymbolTile(snippet.getSFAvatar())
                VStack(alignment: .leading, spacing: 2) {
                    Text(snippet.name.isEmpty ? "Untitled" : snippet.name)
                        .font(.rxBodyStrong)
                        .foregroundStyle(.rxInk)
                        .lineLimit(1)
                    if !detail.isEmpty {
                        HelpText(detail)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: RX.Space.s2)
                Button("Run…") { SnippetActions.run(snippet.id) }
                    .buttonStyle(.rx(size: .small))
            }
            CodeBlock(snippet.code.trimmingCharacters(in: .whitespacesAndNewlines), lineLimit: 4)
        }
        .rxCard()
        .scaleEffect(hovered ? 1.01 : 1)
        .animation(.easeOut(duration: 0.15), value: hovered)
        .contentShape(RoundedRectangle(cornerRadius: RX.Radius.card, style: .continuous))
        .onHover { hovered = $0 }
        .onTapGesture(count: 2, perform: edit)
        .help("Double-click to edit")
        .contextMenu {
            Button("Run…") { SnippetActions.run(snippet.id) }
            Button("Edit…", action: edit)
            Button("Duplicate") { SnippetActions.duplicate(snippet.id) }
            Button("Copy Command") { UIBridge.sendPasteboard(str: snippet.code) }
            Divider()
            Button("Delete…", role: .destructive) { SnippetActions.delete(snippet.id) }
        }
    }
}

enum SnippetActions {
    @MainActor
    static func run(_ id: RDSnippet.ID) {
        let snippet = RayonStore.shared.snippetGroup[id]
        guard !snippet.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            UIBridge.presentError(with: "This snippet has no command to run.")
            return
        }
        ServerPickerPanel.present(
            title: "Run \(snippet.name)",
            lead: "Runs with the shell of each server you pick. Servers need an identity set.",
            confirmTitle: "Run",
            allowsMany: true
        ) { machines in
            mainActor(delay: 0.3) {
                SheetPresenter.present { dismiss in
                    BatchRunSheet(snippet: snippet, machines: machines, close: dismiss)
                }
            }
        }
    }

    static func duplicate(_ id: RDSnippet.ID) {
        var copy = RayonStore.shared.snippetGroup[id]
        copy.id = UUID()
        copy.name += " copy"
        RayonStore.shared.snippetGroup.insert(copy)
    }

    static func delete(_ id: RDSnippet.ID) {
        let snippet = RayonStore.shared.snippetGroup[id]
        UIBridge.requiresConfirmation(
            message: "Delete \(snippet.name.isEmpty ? "this snippet" : snippet.name)?",
            informative: "The command is removed from Rayon.",
            confirmTitle: "Delete",
            destructive: true
        ) { confirmed in
            if confirmed { RayonStore.shared.snippetGroup.delete(id) }
        }
    }
}
