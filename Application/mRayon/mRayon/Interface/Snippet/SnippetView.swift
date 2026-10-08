//
//  SnippetView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/2.
//

import RayonModule
import SwiftUI

struct SnippetView: View {
    @EnvironmentObject var store: RayonStore
    @State private var searchKey = ""
    @State private var openCreate = false

    var filtered: [RDSnippet] {
        let all = store.snippetGroup.snippets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !searchKey.isEmpty else { return all }
        return all.filter { $0.isQualifiedForSearch(text: searchKey.lowercased()) }
    }

    var body: some View {
        Group {
            if store.snippetGroup.snippets.isEmpty {
                EmptyStateView(
                    "No snippets yet",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    message: "Save commands you run often, then run them on several servers at once.",
                    actionTitle: "New Snippet"
                ) {
                    openCreate = true
                }
                .frame(maxHeight: .infinity)
                .background(RXBackdrop().ignoresSafeArea())
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: RX.Space.s3, alignment: .top)], spacing: RX.Space.s3) {
                        ForEach(filtered) { snippet in
                            SnippetElementView(identity: snippet.id)
                        }
                    }
                    .padding(RX.Space.s4)
                }
                .background(RXBackdrop().ignoresSafeArea())
                .searchable(text: $searchKey, prompt: "Search snippets")
            }
        }
        .navigationTitle("Snippets")
        .toolbar {
            ToolbarItem {
                Button {
                    openCreate = true
                } label: {
                    Label("New Snippet", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $openCreate) {
            NavigationStack { EditSnippetView() }
        }
    }
}
