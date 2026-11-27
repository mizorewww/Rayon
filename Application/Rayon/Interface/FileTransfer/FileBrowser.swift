//
//  FileBrowser.swift
//  Rayon
//
//  What a Files page shows and does, on the Mac and on iPhone and iPad: the
//  folder sorted and filtered, the files chosen in it, and the actions on
//  them. The pages only lay it out.
//

import Combine
import RayonModule
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FileBrowser: ObservableObject {
    typealias File = FileTransferContext.RemoteFile

    let context: FileTransferContext

    @Published var filter = "" {
        didSet { if filter != oldValue { applyFilter() } }
    }

    @Published var sortOrder = [RemoteFileComparator(.name)] {
        didSet { if sortOrder != oldValue { arrange(context.currentFileList) } }
    }

    @Published var selection = Set<File.ID>()
    /// What the list shows: the folder in `sortOrder`, less what the filter
    /// leaves out.
    @Published private(set) var files: [File] = []
    /// The question the Mac asks in a sheet; iPhone and iPad ask in an alert.
    @Published var prompt: FilePrompt?

    /// The whole folder in `sortOrder`. Sorted when the folder or the order
    /// changes, not on every redraw: a transfer's progress redraws the page
    /// many times a second.
    private var sorted: [File] = []
    /// Counts the sorts, so a slow sort of an old listing is dropped.
    private var listing = 0
    private var subscriptions: Set<AnyCancellable> = []

    init(context: FileTransferContext) {
        self.context = context
        context.$currentFileList
            .sink { [weak self] list in self?.arrange(list) }
            .store(in: &subscriptions)
        context.$currentDir
            .removeDuplicates()
            .sink { [weak self] _ in self?.selection = [] }
            .store(in: &subscriptions)
    }

    var busy: Bool { context.processConnection || context.isProgressRunning }
    var ready: Bool { !busy && context.connected }
    var canGoUp: Bool { context.currentUrl.pathComponents.count > 1 }
    var selectedFiles: [File] { files.filter { selection.contains($0.id) } }

    /// The Go menu's actions on this page.
    var commands: FileBrowserCommandActions {
        FileBrowserCommandActions(
            back: ready && context.canGoBack ? { [context] in context.goBack() } : nil,
            forward: ready && context.canGoForward ? { [context] in context.goForward() } : nil,
            enclosingFolder: ready && canGoUp ? { [weak self] in self?.goUp() } : nil,
            goToFolder: ready ? { [weak self] in self?.ask(.goTo) } : nil,
            reload: ready ? { [context] in context.loadCurrentFileList() } : nil
        )
    }

    // MARK: Order and filter

    private func arrange(_ list: [File]) {
        listing += 1
        let order = sortOrder
        // A long folder is sorted off the main thread; a short one takes less
        // than a frame, and showing it at once avoids a flash of the old one.
        guard list.count > 1000 else { return show(sorted: list.sorted(using: order)) }
        let expected = listing
        Task {
            let result = await Task.detached(priority: .userInitiated) { list.sorted(using: order) }.value
            if listing == expected { show(sorted: result) }
        }
    }

    private func show(sorted list: [File]) {
        sorted = list
        // A reload reads every file anew; one that is gone is no longer chosen.
        if !selection.isEmpty { selection.formIntersection(list.map(\.id)) }
        applyFilter()
    }

    /// Filtering keeps the order, so typing in the filter never sorts.
    private func applyFilter() {
        files = filter.isEmpty ? sorted : sorted.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    // MARK: Actions

    func goUp() {
        context.navigate(path: context.currentUrl.deletingLastPathComponent().path)
    }

    /// A folder opens; a text file opens in the editor; anything else is
    /// downloaded.
    func open(_ file: File) {
        if file.isFolder {
            context.navigate(path: file.url.path)
        } else if FileTransferContext.isEditable(file) {
            edit(file)
        } else {
            download([file])
        }
    }

    func edit(_ file: File) {
        #if os(macOS)
            AppRouter.shared.openEditor(context: context, path: file.url.path)
        #else
            EditorCenter.shared.workspace(for: context).open(path: file.url.path)
            showEditor()
        #endif
    }

    #if os(iOS)
        /// The server's page switches to its editor.
        func showEditor() {
            SessionNavigation.shared.reveal(.server(context.machine.id), tool: .editor)
        }
    #endif

    /// The Mac asks where to save; iPhone and iPad save to the app's
    /// Documents, which the Files app shows.
    func download(_ files: [File]) {
        guard !files.isEmpty else { return }
        let items = files.map(\.url)
        #if os(macOS)
            let message: LocalizedStringResource = files.count == 1 ? "Choose where to save \(files[0].name)" : "Choose where to save \(files.count) items"
            OpenPanel.present(
                message: message,
                prompt: "Download Here",
                directory: nil,
                canChooseFiles: false,
                canChooseDirectories: true,
                allowsMultipleSelection: false,
                canCreateDirectories: true,
                showsHiddenFiles: false
            ) { [context] urls in
                if let url = urls.first { context.download(from: items, toDir: url) }
            }
        #else
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            context.download(from: items, toDir: documents)
        #endif
    }

    func delete(_ files: [File]) {
        guard let first = files.first else { return }
        let items = files.map(\.url)
        let message: LocalizedStringResource = files.count == 1 ? "Delete \(first.name)?" : "Delete \(files.count) items?"
        let informative: LocalizedStringResource = if files.count > 1 {
            "The items, and everything in the folders among them, are deleted from the server. This cannot be undone."
        } else if first.fstat.isDirectory {
            "The folder and everything in it is deleted from the server. This cannot be undone."
        } else {
            "The file is deleted from the server. This cannot be undone."
        }
        Indicator.confirm(message: message, informative: informative, confirmTitle: "Delete", destructive: true) { [context] confirmed in
            if confirmed { context.delete(items: items) }
        }
    }

    /// Uploads the files dropped on the page; false for a drop that carries
    /// none, so it lands elsewhere.
    func upload(dropped providers: [NSItemProvider]) -> Bool {
        guard ready else { return false }
        #if os(macOS)
            let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        #else
            let matching = providers
        #endif
        guard !matching.isEmpty else { return false }
        let (loaded, loader) = AsyncStream.makeStream(of: URL?.self)
        for provider in matching {
            DroppedFile.load(provider) { loader.yield($0) }
        }
        let expected = matching.count
        Task {
            var urls: [URL] = []
            var count = 0
            for await url in loaded {
                if let url { urls.append(url) }
                count += 1
                if count == expected { break }
            }
            if !urls.isEmpty { context.upload(urls: urls) }
        }
        return true
    }

    // MARK: Prompts

    func ask(_ prompt: FilePrompt) {
        #if os(macOS)
            self.prompt = prompt
        #else
            Indicator.input(title: prompt.title, placeholder: prompt.placeholder, text: initialText(for: prompt)) { [weak self] text in
                guard let self, !text.isEmpty else { return }
                if let problem = problem(with: text, for: prompt) {
                    Indicator.error(problem)
                } else {
                    perform(prompt, with: text)
                }
            }
        #endif
    }

    func initialText(for prompt: FilePrompt) -> String {
        switch prompt {
        case .goTo: context.currentDir
        case .newFolder: ""
        case let .rename(name): name
        }
    }

    /// What is wrong with the answer, said for the person to fix; nil when it
    /// can be used, or is still empty.
    func problem(with text: String, for prompt: FilePrompt) -> String? {
        switch prompt {
        case .goTo:
            return text.hasPrefix("/") || text.isEmpty ? nil : String(localized: "Use an absolute path starting with /.")
        case .newFolder, .rename:
            if text.isEmpty { return nil }
            if !text.isValidAsFilename { return String(localized: "That name contains characters a file name cannot have.") }
            if case let .rename(original) = prompt, original == text { return nil }
            if context.currentFileList.contains(where: { $0.name == text }) { return String(localized: "“\(text)” already exists in this folder.") }
            return nil
        }
    }

    func perform(_ prompt: FilePrompt, with text: String) {
        switch prompt {
        case .goTo:
            context.navigate(path: text)
        case .newFolder:
            context.createFolder(with: text)
        case let .rename(original):
            if original != text {
                let base = context.currentUrl
                context.rename(from: base.appendingPathComponent(original), to: base.appendingPathComponent(text))
            }
        }
    }
}

/// Go to Folder, New Folder and Rename.
enum FilePrompt: Identifiable {
    case goTo
    case newFolder
    case rename(String)

    var id: String {
        switch self {
        case .goTo: "goto"
        case .newFolder: "folder"
        case let .rename(name): "rename-\(name)"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .goTo: "Go to Folder"
        case .newFolder: "New Folder"
        case .rename: "Rename"
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .goTo: "Path"
        case .newFolder, .rename: "Name"
        }
    }

    var placeholder: LocalizedStringResource {
        switch self {
        case .goTo: "/var/log"
        case .newFolder: "untitled folder"
        case .rename: "Name"
        }
    }

    var confirmTitle: LocalizedStringResource {
        switch self {
        case .goTo: "Go"
        case .newFolder: "Create"
        case .rename: "Rename"
        }
    }

    var isPath: Bool {
        if case .goTo = self { return true }
        return false
    }
}

/// A file dropped from Finder or another app.
private enum DroppedFile {
    /// Hands the dropped file's URL, or nil, to `done` on a background queue.
    static func load(_ provider: NSItemProvider, done: @escaping @Sendable (URL?) -> Void) {
        #if os(macOS)
            _ = provider.loadObject(ofClass: URL.self) { url, _ in done(url) }
        #else
            // The file given is removed when the handler returns: it is
            // copied out first.
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, _ in
                guard let url else { return done(nil) }
                let staging = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Upload-\(UUID().uuidString)", isDirectory: true)
                let copy = staging.appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: copy)
                    done(copy)
                } catch {
                    done(nil)
                }
            }
        #endif
    }
}
