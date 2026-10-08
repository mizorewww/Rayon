//
//  FileTransferPage.swift
//  Rayon (macOS)
//
//  SFTP inside the main window: Up, breadcrumb, Go to Folder, filter, Reload,
//  New Folder, Upload, Download. Table: name, size, modified, permissions, owner.
//  Transfer card with speed and Cancel. Drag files in to upload.
//

import RayonModule
import SwiftUI
import UniformTypeIdentifiers

struct FileTransferPage: View {
    @ObservedObject var context: FileTransferContext
    @EnvironmentObject var store: RayonStore

    @State private var filter = ""
    @State private var selection: FileTransferContext.RemoteFile?
    @State private var prompt: FilePrompt?
    @State private var dropTargeted = false

    var files: [FileTransferContext.RemoteFile] {
        let list = context.currentFileList.sorted { lhs, rhs in
            if lhs.fstat.isDirectory != rhs.fstat.isDirectory { return lhs.fstat.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        guard !filter.isEmpty else { return list }
        return list.filter { $0.name.lowercased().contains(filter.lowercased()) }
    }

    var busy: Bool { context.processConnection || context.isProgressRunning }

    var body: some View {
        PageScaffold(scrolls: false, search: $filter, searchPrompt: "Filter") {
            ToolbarAction("Enclosing Folder", systemImage: "arrow.up") { goUp() }
                .disabled(context.currentUrl.pathComponents.count <= 1 || busy || !context.connected)
                .keyboardShortcut(.upArrow, modifiers: .command)
            ToolbarAction("Go to Folder", systemImage: "arrow.turn.down.right") { prompt = .goTo }
                .disabled(busy || !context.connected)
                .keyboardShortcut("g", modifiers: [.command, .shift])
        } trailing: {
            ToolbarAction("Reload", systemImage: "arrow.clockwise") { context.loadCurrentFileList() }
                .disabled(busy || !context.connected)
                .keyboardShortcut("r", modifiers: .command)
            ToolbarAction("New Folder", systemImage: "folder.badge.plus") { prompt = .newFolder }
                .disabled(busy || !context.connected)
            ToolbarAction("Upload", systemImage: "arrow.up.doc") { upload() }
                .disabled(busy || !context.connected)
            ToolbarAction("Download", systemImage: "arrow.down.doc", primary: true) {
                if let selection { download(selection) }
            }
            .disabled(selection == nil || busy || !context.connected)
        } header: {
            VStack(alignment: .leading, spacing: RX.Space.s2) {
                PageTitle(store.machineRedacted == .all ? "File Transfer" : context.machine.name, subtitle: subtitle)
                Breadcrumb(url: context.currentUrl) { path in
                    context.navigate(path: path)
                }
                .disabled(busy || !context.connected)
            }
        } content: {
            VStack(spacing: RX.Space.s4) {
                if context.destroyedSession || (!context.connected && !context.processConnection) {
                    EmptyStateView(
                        "Connection closed",
                        systemImage: "bolt.horizontal",
                        message: context.currentHint.isEmpty ? "The file transfer is no longer connected." : context.currentHint,
                        actionTitle: context.destroyedSession ? nil : "Reconnect"
                    ) {
                        context.processBootstrap()
                    }
                    .rxCard()
                    Spacer()
                } else if context.processConnection, context.currentFileList.isEmpty {
                    VStack(spacing: RX.Space.s3) {
                        ProgressView()
                        Text(context.currentHint.isEmpty ? "Connecting…" : context.currentHint)
                            .font(.rxBody)
                            .foregroundStyle(.rxInkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(RX.Space.s6)
                    .rxCard()
                    Spacer()
                } else {
                    fileTable
                }
                if context.isProgressRunning, !context.processConnection {
                    transferCard
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: RX.Radius.card, style: .continuous)
                    .strokeBorder(Color.rxAccent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Color.rxAccentFill.clipShape(RoundedRectangle(cornerRadius: RX.Radius.card, style: .continuous)))
                    .overlay(
                        Label("Drop to upload to \(context.currentDir)", systemImage: "arrow.up.doc")
                            .font(.rxBodyStrong)
                            .foregroundStyle(.rxAccent)
                    )
                    .padding(RX.Space.s4)
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $prompt) { prompt in
            FilePromptSheet(prompt: prompt, context: context) { self.prompt = nil }
        }
        .onChange(of: context.currentDir) { _ in selection = nil }
    }

    var subtitle: String {
        var parts = ["SFTP"]
        if store.machineRedacted == .none {
            parts.append(context.machine.getCommand(insertLeadingSSH: false))
        }
        if context.connected {
            parts.append("\(files.count) item\(files.count == 1 ? "" : "s")")
            parts.append("drag files here to upload")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Table

    var fileTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TableHeaderLabel("Name").frame(maxWidth: .infinity)
                TableHeaderLabel("Size", alignment: .trailing).frame(width: 90)
                Color.clear.frame(width: RX.Space.s4, height: 1)
                TableHeaderLabel("Modified").frame(width: 150)
                TableHeaderLabel("Permissions").frame(width: 110)
                TableHeaderLabel("Owner").frame(width: 70)
            }
            .padding(.horizontal, RX.Space.s3)
            .frame(height: RX.tableHeaderHeight)
            Hairline()
            if files.isEmpty {
                EmptyStateView(
                    filter.isEmpty ? "Empty folder" : "No matches",
                    systemImage: "folder",
                    message: filter.isEmpty ? "Drag files here to upload them." : "No file matches “\(filter)”."
                )
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(files) { file in
                            FileRow(file: file, selected: selection == file)
                                .onTapGesture(count: 2) { open(file) }
                                .simultaneousGesture(TapGesture().onEnded { selection = file })
                                .contextMenu { menu(for: file) }
                        }
                    }
                }
            }
        }
        .padding(RX.Space.s2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear.rxCard(padding: 0))
        .disabled(busy)
        .opacity(busy ? 0.6 : 1)
    }

    @ViewBuilder
    func menu(for file: FileTransferContext.RemoteFile) -> some View {
        if file.fstat.isDirectory {
            Button("Open") { open(file) }
        }
        Button("Download…") { download(file) }
        Divider()
        Button("Rename…") { prompt = .rename(file.name) }
        Button("Copy Name") { UIBridge.sendPasteboard(str: file.name) }
        Button("Copy Path") { UIBridge.sendPasteboard(str: context.currentUrl.appendingPathComponent(file.name).path) }
        Divider()
        Button("Delete…", role: .destructive) { delete(file) }
    }

    // MARK: Transfer card

    var transferCard: some View {
        let total = context.totalProgress
        let current = context.currentProgress
        let fraction: Double? = total.totalUnitCount > 0
            ? total.fractionCompleted
            : (current.totalUnitCount > 0 ? current.fractionCompleted : nil)
        var detail: [String] = []
        if total.totalUnitCount > 1 {
            detail.append("\(total.completedUnitCount) of \(total.totalUnitCount)")
        }
        if context.currentSpeed > 0 {
            detail.append(RXFormat.rateString(Double(context.currentSpeed)))
        }
        let name = context.currentProcessingFile.isEmpty
            ? (context.currentHint.isEmpty ? "Working…" : context.currentHint)
            : URL(fileURLWithPath: context.currentProcessingFile).lastPathComponent
        return VStack(alignment: .leading, spacing: RX.Space.s2) {
            CardHead("Transfer")
            ProgressRowView(
                title: name,
                detail: detail.joined(separator: " · "),
                fraction: fraction,
                cancel: context.currentProgressCancelable && context.continueCurrentProgress
                    ? { context.continueCurrentProgress = false }
                    : nil
            )
        }
        .rxCard()
    }

    // MARK: Actions

    func goUp() {
        context.navigate(path: context.currentUrl.deletingLastPathComponent().path)
    }

    func open(_ file: FileTransferContext.RemoteFile) {
        if file.fstat.isDirectory {
            context.navigate(path: context.currentUrl.appendingPathComponent(file.name).path)
        } else {
            download(file)
        }
    }

    func upload() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"
        panel.message = "Upload to \(context.currentDir)"
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK { context.upload(urls: panel.urls) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(panel.runModal())
        }
    }

    func download(_ file: FileTransferContext.RemoteFile) {
        let remote = context.currentUrl.appendingPathComponent(file.name)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Download Here"
        panel.message = "Choose where to save \(file.name)"
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url {
                context.download(from: remote, toDir: url)
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(panel.runModal())
        }
    }

    func delete(_ file: FileTransferContext.RemoteFile) {
        let item = context.currentUrl.appendingPathComponent(file.name)
        UIBridge.requiresConfirmation(
            message: "Delete \(file.name)?",
            informative: file.fstat.isDirectory
                ? "The folder and everything in it is deleted from the server. This cannot be undone."
                : "The file is deleted from the server. This cannot be undone.",
            confirmTitle: "Delete",
            destructive: true
        ) { confirmed in
            if confirmed { context.delete(item: item) }
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard context.connected, !busy else { return false }
        let group = DispatchGroup()
        nonisolated(unsafe) var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { context.upload(urls: urls) }
        }
        return true
    }
}

// MARK: - Rows

private struct FileRow: View {
    let file: FileTransferContext.RemoteFile
    let selected: Bool
    @State private var hovered = false

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: RX.Space.s2) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(file.fstat.isDirectory ? Color.rxAccent : Color.rxInkSecondary)
                    .frame(width: 18)
                Text(file.name)
                    .font(.rxBody)
                    .foregroundStyle(.rxInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(file.fstat.isDirectory ? "—" : RXFormat.bytesString(Double(truncating: file.fstat.size ?? 0)))
                .font(.rxBody.monospacedDigit())
                .foregroundStyle(file.fstat.isDirectory ? Color.rxInkSecondary : Color.rxInk)
                .frame(width: 90, alignment: .trailing)
            Color.clear.frame(width: RX.Space.s4, height: 1)
            Text(file.fstat.modificationDate.map { Self.dateFormatter.string(from: $0) } ?? "—")
                .font(.rxBody)
                .foregroundStyle(.rxInkSecondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            Text(file.fstat.permissionDescription)
                .font(.rxCode)
                .foregroundStyle(.rxInkSecondary)
                .frame(width: 110, alignment: .leading)
            Text("\(file.fstat.ownerUID)")
                .font(.rxBody.monospacedDigit())
                .foregroundStyle(.rxInkSecondary)
                .frame(width: 70, alignment: .leading)
        }
        .padding(.horizontal, RX.Space.s3)
        .frame(height: RX.denseRowHeight)
        .rxRowBackground(selected: selected, hovered: hovered)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    var icon: String {
        if file.fstat.isDirectory { return "folder" }
        if file.fstat.isLink { return "link" }
        return "doc"
    }
}

/// The current remote folder: one clickable segment per folder, the last in `ink` semibold.
/// Long paths collapse middle segments into "…".
struct Breadcrumb: View {
    let url: URL
    let navigate: (String) -> Void

    var body: some View {
        let components = url.pathComponents
        let indices = Array(components.indices)
        let shown: [Int?] = indices.count > 5
            ? [indices[0], nil] + indices.suffix(3).map { Optional($0) }
            : indices.map { Optional($0) }
        HStack(spacing: 2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { position, index in
                if position > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.rxInkTertiary)
                }
                if let index {
                    let isLast = index == components.count - 1
                    Button {
                        navigate(path(upTo: index))
                    } label: {
                        Text(components[index])
                            .font(.system(size: 13, weight: isLast ? .semibold : .regular))
                            .foregroundStyle(isLast ? Color.rxInk : Color.rxInkSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .frame(height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLast)
                } else {
                    Text("…").foregroundStyle(.rxInkSecondary)
                }
            }
        }
        .layoutPriority(1)
    }

    func path(upTo index: Int) -> String {
        let components = url.pathComponents.prefix(index + 1)
        guard components.count > 1 else { return "/" }
        return "/" + components.dropFirst().joined(separator: "/")
    }
}

// MARK: - Prompts

enum FilePrompt: Identifiable {
    case goTo
    case newFolder
    case rename(String)

    var id: String {
        switch self {
        case .goTo: return "goto"
        case .newFolder: return "folder"
        case let .rename(name): return "rename-\(name)"
        }
    }
}

/// Go to Folder, New Folder and Rename as small sheets.
private struct FilePromptSheet: View {
    let prompt: FilePrompt
    @ObservedObject var context: FileTransferContext
    let close: () -> Void

    @State private var text = ""

    var title: String {
        switch prompt {
        case .goTo: return "Go to Folder"
        case .newFolder: return "New Folder"
        case .rename: return "Rename"
        }
    }

    var error: String? {
        switch prompt {
        case .goTo:
            return text.hasPrefix("/") || text.isEmpty ? nil : "Use an absolute path starting with /."
        case .newFolder, .rename:
            if text.isEmpty { return nil }
            if !text.isValidAsFilename { return "That name contains characters a file name cannot have." }
            if case let .rename(original) = prompt, original == text { return nil }
            if context.currentFileList.contains(where: { $0.name == text }) { return "“\(text)” already exists in this folder." }
            return nil
        }
    }

    var body: some View {
        SheetScaffold(title) {
            RXField(prompt.label, error: error) {
                TextField(prompt.placeholder, text: $text)
                    .textFieldStyle(prompt.isPath ? .rxMono : .rx)
                    .disableAutocorrection(true)
                    .onSubmit(confirm)
            }
        } footer: {
            Spacer()
            Button("Cancel", action: close)
                .buttonStyle(.rx)
                .keyboardShortcut(.cancelAction)
            Button(prompt.confirmTitle, action: confirm)
                .buttonStyle(.rxPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(text.isEmpty || error != nil)
        }
        .frame(width: 420)
        .onAppear {
            switch prompt {
            case .goTo: text = context.currentDir
            case .newFolder: text = ""
            case let .rename(name): text = name
            }
        }
    }

    func confirm() {
        guard !text.isEmpty, error == nil else { return }
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
        close()
    }
}

private extension FilePrompt {
    var label: String {
        switch self {
        case .goTo: return "Path"
        case .newFolder, .rename: return "Name"
        }
    }

    var placeholder: String {
        switch self {
        case .goTo: return "/var/log"
        case .newFolder: return "untitled folder"
        case .rename: return "Name"
        }
    }

    var confirmTitle: String {
        switch self {
        case .goTo: return "Go"
        case .newFolder: return "Create"
        case .rename: return "Rename"
        }
    }

    var isPath: Bool {
        if case .goTo = self { return true }
        return false
    }
}

enum FileTransferSessionActions {
    static func close(_ context: FileTransferContext) {
        if context.isProgressRunning {
            UIBridge.requiresConfirmation(
                message: "Close the file transfer on \(context.machine.name)?",
                informative: "A transfer is still running and will be interrupted.",
                confirmTitle: "Close",
                destructive: true
            ) { confirmed in
                if confirmed { FileTransferManager.shared.end(for: context.id) }
            }
        } else {
            FileTransferManager.shared.end(for: context.id)
        }
    }
}
