//
//  LibrariesView.swift
//  Rayon
//
//  Settings › About › Libraries: what the app ships, each with its
//  repository and license, and the license's full text. On the Mac a sheet
//  with the list beside the text; on the iPhone and iPad a list that pushes it.
//  In Debug, `RAYON_PREVIEW_LIBRARIES=[name]` opens it (and that library's
//  license) from About, for screenshots without input.
//

import RayonModule
import SwiftUI

struct LibrariesView: View {
    @State private var search = ""
    #if os(macOS)
        @Environment(\.dismiss) private var dismiss
        @State private var selection: LibraryNotice.ID? = Self.previewLibrary?.id ?? LibraryNotice.bundled.first?.id
    #else
        @State private var shown: LibraryNotice?
    #endif

    /// The library `RAYON_PREVIEW_LIBRARIES` names.
    private static var previewLibrary: LibraryNotice? {
        #if DEBUG
            LibraryNotice.bundled.first { $0.name == ProcessInfo.processInfo.environment["RAYON_PREVIEW_LIBRARIES"] }
        #else
            nil
        #endif
    }

    private var libraries: [LibraryNotice] {
        let words = search.lowercased().split(whereSeparator: \.isWhitespace)
        return LibraryNotice.bundled.filter { library in
            let text = "\(library.name) \(library.repository ?? "") \(library.license ?? "")".lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    var body: some View {
        #if os(macOS)
            NavigationSplitView {
                List(libraries, selection: $selection) { LibraryRow(library: $0) }
                    .overlay { emptySearch }
                    .navigationSplitViewColumnWidth(min: 300, ideal: 330)
            } detail: {
                if let library = LibraryNotice.bundled.first(where: { $0.id == selection }) {
                    LibraryLicenseView(library: library)
                } else {
                    ContentUnavailableView("No Library Selected", systemImage: "books.vertical")
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search libraries")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .frame(minWidth: 920, minHeight: 540)
        #else
            List(libraries) { library in
                NavigationLink {
                    LibraryLicenseView(library: library)
                } label: {
                    LibraryRow(library: library)
                }
            }
            .overlay { emptySearch }
            .searchable(text: $search, prompt: "Search libraries")
            .navigationTitle("Libraries")
            .navigationDestination(item: $shown) { LibraryLicenseView(library: $0) }
            .task { shown = Self.previewLibrary }
        #endif
    }

    @ViewBuilder private var emptySearch: some View {
        if libraries.isEmpty, !search.isEmpty {
            ContentUnavailableView.search(text: search)
        }
    }
}

/// The name and version, the repository as a link, the license as a badge.
private struct LibraryRow: View {
    let library: LibraryNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(library.name)
                if let version = library.version {
                    Text(version)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if let url = library.url, let repository = library.repository {
                // Borderless, so on iOS a tap on it opens the page instead
                // of pushing the row.
                Link(destination: url) {
                    Text(repository)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.callout)
                .buttonStyle(.borderless)
                .help(url.absoluteString)
            }
        }
        .badge(Text(library.license ?? String(localized: "No license file")))
    }
}

/// The library, its repository and license over the license's full text,
/// monospaced and selectable.
private struct LibraryLicenseView: View {
    let library: LibraryNotice

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(library.name)
                        .font(.title2.weight(.semibold))
                    if let url = library.url, let repository = library.repository {
                        Link(destination: url) {
                            Label(repository, systemImage: "arrow.up.right.square")
                        }
                        .help(url.absoluteString)
                    }
                    Text([library.version, library.license ?? String(localized: "No license file")].compactMap(\.self).joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
                Divider()
                Text(library.text)
                    .font(Self.textFont)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(library.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Small enough on the Mac that an 80-column license keeps its lines.
    #if os(macOS)
        private static let textFont = Font.system(size: 11, design: .monospaced)
    #else
        private static let textFont = Font.footnote.monospaced()
    #endif
}
