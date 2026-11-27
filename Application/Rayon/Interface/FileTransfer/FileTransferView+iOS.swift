//
//  FileTransferView+iOS.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/3/18.
//

#if os(iOS)
    import RayonModule
    import SwiftUI
    import UIKit
    import UniformTypeIdentifiers

    struct FileTransferView: View {
        @ObservedObject var context: FileTransferContext
        @StateObject private var browser: FileBrowser
        @Environment(\.dismiss) private var dismiss
        @Environment(\.inServerWorkspace) private var inServerWorkspace

        @State var openFilePicker: Bool = false
        @State private var dropTargeted = false
        /// Select chooses several files for Download or Delete.
        @State private var editMode: EditMode = .inactive

        init(context: FileTransferContext) {
            self.context = context
            _browser = StateObject(wrappedValue: FileBrowser(context: context))
        }

        var busy: Bool { browser.busy }

        var body: some View {
            Group {
                if context.destroyedSession {
                    EmptyStateView("Connection closed", systemImage: "bolt.horizontal")
                } else {
                    VStack(spacing: RX.Space.s3) {
                        mainView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Group {
                            if editMode.isEditing {
                                selectionBar
                            } else {
                                bottomToolbar
                            }
                        }
                        .disabled(context.processConnection)
                        .disabled(context.isProgressRunning)
                        hintView
                    }
                }
            }
            .padding(.horizontal, RX.Space.s4)
            .padding(.bottom, RX.Space.s3)
            .background(RXBackdrop().ignoresSafeArea())
            .animation(.interactiveSpring(), value: context.currentFileList)
            .animation(.interactiveSpring(), value: context.currentHint)
            .animation(.interactiveSpring(), value: context.currentProcessingFile)
            .animation(.interactiveSpring(), value: context.processConnection)
            .navigationTitle(context.machine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { actionsToolbar }
            .sheet(isPresented: $openFilePicker, onDismiss: nil) {
                FilePickerUIRepresentable(types: [.item], allowMultiple: true) { urls in
                    context.upload(urls: urls)
                }
            }
            // iPad: files dragged in from Files or another app are uploaded here.
            .onDrop(of: [.item], isTargeted: $dropTargeted, perform: browser.upload(dropped:))
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: RX.Radius.card, style: .continuous)
                        .strokeBorder(Color.rxAccent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .background(Color.rxAccentFill.clipShape(RoundedRectangle(cornerRadius: RX.Radius.card, style: .continuous)))
                        .overlay(
                            Label("Drop to upload to \(context.currentDir)", systemImage: "arrow.up.doc")
                                .font(.headline)
                                .foregroundStyle(.rxAccent)
                        )
                        .padding(RX.Space.s4)
                        .allowsHitTesting(false)
                }
            }
            .focusedSceneValue(\.fileBrowserCommands, browser.commands)
            .environment(\.editMode, $editMode)
            #if DEBUG
                // RAYON_PREVIEW_SELECT=<n> chooses the first n files, for screenshots without input.
                .onReceive(browser.$files) { files in
                    guard let count = ProcessInfo.processInfo.environment["RAYON_PREVIEW_SELECT"].flatMap(Int.init),
                          !files.isEmpty, browser.selection.isEmpty
                    else { return }
                    editMode = .active
                    browser.selection = Set(files.prefix(count).map(\.id))
                }
            #endif
            .onChange(of: context.connected) { _, connected in
                if !connected { editMode = .inactive }
            }
        }

        var mainView: some View {
            Group {
                if context.isProgressRunning || context.processConnection {
                    progressView
                } else if !context.connected {
                    EmptyStateView(
                        "Connection closed",
                        systemImage: "bolt.horizontal",
                        message: context.connectionPhase == .closed ? nil : "\(context.currentHint)",
                        actionTitle: "Reconnect"
                    ) {
                        context.processBootstrap()
                    }
                    .rxCard()
                } else {
                    fileListView
                }
            }
        }

        var hintView: some View {
            Group {
                if !context.currentHint.isEmpty {
                    HelpText(verbatim: context.currentHint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        var progressView: some View {
            TransferCard(context: context)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, RX.Space.s3)
        }

        var fileListView: some View {
            Group {
                if context.currentFileList.isEmpty {
                    EmptyStateView("Empty folder", systemImage: "folder")
                } else {
                    List(selection: $browser.selection) {
                        Section {
                            ForEach(browser.files) { file in
                                RemoteFileRow(file: file, browser: browser)
                            }
                        } header: {
                            Text("\(browser.files.count) items")
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .searchable(text: $browser.filter)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        /// While selecting: choose all, and what can be done to the chosen files.
        var selectionBar: some View {
            let chosen = browser.selectedFiles
            let allChosen = !browser.files.isEmpty && chosen.count == browser.files.count
            return HStack {
                Button(allChosen ? "Deselect All" : "Select All") {
                    browser.selection = allChosen ? [] : Set(browser.files.map(\.id))
                }
                .disabled(browser.files.isEmpty)
                Spacer()
                Button { browser.download(chosen) } label: {
                    Label("Download", systemImage: "arrow.down.doc")
                }
                .disabled(chosen.isEmpty)
                Button { browser.delete(chosen) } label: {
                    Label("Delete…", systemImage: "trash")
                }
                .tint(.rxDanger)
                .disabled(chosen.isEmpty)
            }
            .buttonStyle(.rx(size: .small))
            .frame(maxWidth: .infinity)
        }

        /// Where the list is, and the way up or elsewhere. What can be done to
        /// the folder is in the bar's Actions menu, by name.
        var bottomToolbar: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button { context.goBack() } label: {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.rx(size: .small))
                    .disabled(!context.connected || !context.canGoBack)
                    Button { context.goForward() } label: {
                        Label("Forward", systemImage: "chevron.right")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.rx(size: .small))
                    .disabled(!context.connected || !context.canGoForward)
                    Button { browser.goUp() } label: {
                        Label("Up", systemImage: "arrow.up")
                    }
                    .buttonStyle(.rx(size: .small))
                    .disabled(!context.connected || !browser.canGoUp)
                    Button { browser.ask(.goTo) } label: {
                        Label("Go to…", systemImage: "arrow.right")
                    }
                    .buttonStyle(.rx(size: .small))
                    .disabled(!context.connected)
                    Divider().frame(height: 20)
                    FolderBreadcrumb(url: context.currentUrl) { path in
                        context.navigate(path: path)
                    }
                    .disabled(!context.connected)
                }
            }
            .frame(maxWidth: .infinity)
        }

        /// The folder's actions, each by name; the one people reach for most,
        /// Upload, beside them.
        @ToolbarContentBuilder var actionsToolbar: some ToolbarContent {
            ToolbarItemGroup(placement: .primaryAction) {
                if context.connected, !context.currentFileList.isEmpty {
                    // "Cancel", like Photos: the page's own Done, beside it, closes Files.
                    Button(editMode.isEditing ? "Cancel" : "Select") {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                            if !editMode.isEditing { browser.selection = [] }
                        }
                    }
                    .disabled(busy && !editMode.isEditing)
                }
                if context.connected, !editMode.isEditing {
                    Button { openFilePicker = true } label: {
                        Label("Upload", systemImage: "arrow.up.doc")
                    }
                    .disabled(busy)
                }
                Menu {
                    Button { browser.ask(.newFolder) } label: {
                        Label("New Folder…", systemImage: "folder.badge.plus")
                    }
                    .disabled(!context.connected || busy)
                    Button { openFilePicker = true } label: {
                        Label("Upload Files…", systemImage: "arrow.up.doc")
                    }
                    .disabled(!context.connected || busy)
                    Button { context.loadCurrentFileList() } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(!context.connected || busy)
                    Button { browser.showEditor() } label: {
                        Label("Open Editor", systemImage: "square.and.pencil")
                    }
                    Section {
                        sortMenu
                    }
                    Section {
                        Button { FilesApp.showDocuments() } label: {
                            Label("Show Downloads in Files", systemImage: "doc.viewfinder")
                        }
                    }
                    Section {
                        if !context.connected {
                            Button { context.processBootstrap() } label: {
                                Label("Reconnect", systemImage: "arrow.counterclockwise")
                            }
                            .disabled(context.processConnection)
                        }
                        // Stays available while a connection attempt hangs.
                        Button(role: .destructive) { closeOrDisconnect() } label: {
                            Label(context.connected ? "Disconnect" : "Close Files", systemImage: "xmark")
                        }
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
        }

        /// The column the list sorts by and which way, as the Mac's table headers.
        var sortMenu: some View {
            let current = browser.sortOrder.first ?? RemoteFileComparator(.name)
            return Menu {
                Picker("Sort By", selection: Binding(
                    get: { current.field },
                    set: { browser.sortOrder = [RemoteFileComparator($0, order: current.order)] }
                )) {
                    ForEach(RemoteFileComparator.Field.allCases, id: \.self) { field in
                        Text(field.title).tag(field)
                    }
                }
                Picker("Order", selection: Binding(
                    get: { current.order },
                    set: { browser.sortOrder = [RemoteFileComparator(current.field, order: $0)] }
                )) {
                    Text("Ascending").tag(SortOrder.forward)
                    Text("Descending").tag(SortOrder.reverse)
                }
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
            }
        }

        func closeOrDisconnect() {
            if context.connected {
                context.processShutdown()
            } else {
                // On a server's page, the page stays for its other tools.
                FileTransferSessionActions.close(context) { if !inServerWorkspace { dismiss() } }
            }
        }

        /// A file in the list: tap opens it, a swipe downloads, renames or
        /// deletes it, and its menu has the rest. While selecting, a tap
        /// chooses it.
        struct RemoteFileRow: View {
            let file: FileTransferContext.RemoteFile
            @ObservedObject var browser: FileBrowser
            @Environment(\.editMode) private var editMode

            var body: some View {
                Group {
                    if editMode?.wrappedValue.isEditing == true {
                        content
                    } else {
                        Button { browser.open(file) } label: { content }
                            .buttonStyle(.plain)
                    }
                }
                .contextMenu { FileActionsMenu(browser: browser, files: [file]) }
                .swipeActions(edge: .leading) {
                    Button { browser.download([file]) } label: {
                        Label("Download", systemImage: "arrow.down.doc")
                    }
                    .tint(.rxAccent)
                }
                // Not a destructive role: that removes the row before Delete is confirmed.
                .swipeActions(edge: .trailing) {
                    Button { browser.delete([file]) } label: {
                        Label("Delete…", systemImage: "trash")
                    }
                    .tint(.rxDanger)
                    Button { browser.ask(.rename(file.name)) } label: {
                        Label("Rename…", systemImage: "pencil")
                    }
                }
            }

            var content: some View {
                HStack(spacing: RX.Space.s3) {
                    Image(systemName: file.symbol)
                        .foregroundStyle(file.isFolder ? Color.rxAccent : Color.rxInkSecondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .foregroundStyle(.rxInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(detail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.rxInkSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if editMode?.wrappedValue.isEditing != true {
                        Menu {
                            FileActionsMenu(browser: browser, files: [file])
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(.rxInkTertiary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Actions for \(file.name)")
                    }
                }
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }

            /// Size (for a file), modified, permissions and owner, as the Mac's columns.
            var detail: String {
                var parts: [String] = []
                if !file.isFolder { parts.append(file.sizeText) }
                if file.fstat.modificationDate != nil { parts.append(file.modifiedText) }
                parts.append(file.fstat.permissionDescription)
                parts.append(file.ownerText)
                return parts.joined(separator: " · ")
            }
        }
    }

    /// Bridges RayonModule's shared file-transfer core to the iOS app's UI.
    /// RayonModule calls it on the main thread.
    @MainActor
    final class IOSFileTransferUIHandler: @preconcurrency FileTransferUIHandler {
        func presentError(_ message: String) {
            Indicator.error(message)
        }

        func requiresConfirmation(_ message: String, completion: @escaping (Bool) -> Void) {
            Indicator.confirm(message: "\(message)", destructive: true, confirmation: completion)
        }

        func autoOpenInterface(_ context: FileTransferContext) {
            SessionNavigation.shared.reveal(.server(context.machine.id), tool: .files)
        }

        func downloadCompleted() {
            Indicator.success("Download Completed", message: "Saved to Files")
        }
    }

#endif
