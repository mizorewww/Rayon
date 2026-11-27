//
//  LogView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/14.
//

import RayonModule
import SwiftUI

struct LogView: View {
    @State private var lines: [String] = []
    @State private var searchText: String = ""

    private var filteredLines: [String] {
        guard !searchText.isEmpty else { return lines }
        return lines.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            if filteredLines.isEmpty {
                Text("No diagnostic entries")
                    .font(.rxCode)
                    .foregroundStyle(.rxInkSecondary)
            } else {
                ForEach(Array(filteredLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.rxInk)
                        .textSelection(.enabled)
                        .contextMenu {
                            Button {
                                UIBridge.sendPasteboard(str: line)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Filter logs")
        .refreshable {
            await reloadLogs()
        }
        .task {
            await reloadLogs()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Diagnostic")
        .toolbar {
            ToolbarItem {
                // The log file itself, not its text: it can be megabytes,
                // more than belongs on the clipboard.
                ShareLink(item: LogStore.shared.logFileURL) {
                    Label("Share Diagnostic Data", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func reloadLogs() async {
        let loaded: [String] = await Task.detached(priority: .utility) {
            let text = LogStore.shared.readTail(maxBytes: 1024 * 1024)
            let split = text.components(separatedBy: "\n").filter { !$0.isEmpty }
            return Array(split.reversed().prefix(4096))
        }.value
        lines = loaded
    }
}
