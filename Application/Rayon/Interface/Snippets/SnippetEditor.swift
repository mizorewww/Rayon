//
//  SnippetEditor.swift
//  Rayon
//
//  New / Edit Snippet: Name, Group, Comment; Icon (a grid of SF Symbols
//  and the full picker); the command, highlighted as shell.
//

import RayonEditor
import RayonModule
import SwiftUI
import SymbolPicker

struct SnippetEditor: View {
    /// nil creates a new snippet.
    let snippet: RDSnippet.ID?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var group = ""
    @State private var code = "#!/bin/bash\n"
    @State private var comment = ""
    @State private var symbol = "terminal"
    @State private var showsAllSymbols = false

    /// SF Symbols offered in the icon grid.
    private static let symbols = [
        "terminal", "chevron.left.forwardslash.chevron.right", "arrow.clockwise", "power",
        "trash", "externaldrive", "cpu", "memorychip", "network", "globe", "lock", "key",
        "shippingbox", "hammer", "wrench.and.screwdriver", "doc.text", "folder", "clock",
        "bolt", "flame", "ladybug", "chart.bar", "server.rack", "magnifyingglass",
    ]

    init(snippet: RDSnippet.ID?) {
        self.snippet = snippet
        if let read = snippet.flatMap({ RayonStore.shared.snippet($0) }) {
            _name = State(initialValue: read.name)
            _group = State(initialValue: read.group)
            _code = State(initialValue: read.code)
            _comment = State(initialValue: read.comment)
            _symbol = State(initialValue: read.displaySymbol)
        }
    }

    private var isNew: Bool { snippet == nil }

    /// The grid always shows the current symbol.
    private var symbolChoices: [String] {
        Self.symbols.contains(symbol) ? Self.symbols : [symbol] + Self.symbols.dropLast()
    }

    var body: some View {
        Form {
            Section {
                FormField("Name", text: $name, prompt: Text("Restart nginx"))
                FormField("Group", text: $group, prompt: Text("Default"))
                FormField("Comment", text: $comment, prompt: Text("Optional"))
            }
            Section("Icon") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 4)], spacing: 4) {
                    ForEach(symbolChoices, id: \.self) { item in
                        Button {
                            symbol = item
                        } label: {
                            Image(systemName: item)
                                .foregroundStyle(symbol == item ? Color.rxOnAccent : Color.rxInkSecondary)
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(symbol == item ? Color.rxAccent : Color.clear)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(item)
                        .accessibilityLabel(item)
                    }
                }
                // Picking a symbol closes it; going back leaves the symbol as it was.
                Button("More Symbols…") { showsAllSymbols = true }
                    .popover(isPresented: $showsAllSymbols) {
                        SymbolPicker(symbol: $symbol)
                    }
            }
            Section("Command") {
                CodeEditor(
                    text: $code,
                    language: .bash,
                    wrapsLines: true,
                    fontSize: CGFloat(AppSettings.terminalFontSize.value)
                )
                .frame(height: 200)
            }
            if let snippet {
                Section {
                    Button("Delete Snippet", systemImage: "trash", role: .destructive) {
                        SnippetActions.delete(snippet) { dismiss() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Create" : "Save", action: save)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .editorSheet(isNew ? "New Snippet" : "Edit Snippet")
    }

    private func save() {
        let store = RayonStore.shared
        var target = snippet.flatMap { store.snippet($0) } ?? RDSnippet(name: "", group: "", code: "", comment: "")
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.group = group
        target.code = code
        target.comment = comment
        target.symbol = symbol
        store.save(target)
        dismiss()
    }
}
