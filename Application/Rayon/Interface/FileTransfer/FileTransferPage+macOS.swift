//
//  FileTransferPage+macOS.swift
//  Rayon
//
//  SFTP inside the main window: Back, Forward, Up, breadcrumb, Go to Folder, filter, Reload,
//  New Folder, Upload, Download. Table: name, size, modified, permissions, owner.
//  Transfer card with speed and Cancel. Drag files in to upload. Double-click a
//  file to edit it.
//

#if os(macOS)
    import RayonModule
    import SwiftUI
    import UniformTypeIdentifiers

    struct FileTransferPage: View {
        @ObservedObject var context: FileTransferContext
        @StateObject private var browser: FileBrowser
        @EnvironmentObject var store: RayonStore
        @AppSetting(AppSettings.serverRedaction) private var redaction

        @State private var dropTargeted = false
        @State private var pointerHistory = FolderHistoryPointer()

        init(context: FileTransferContext) {
            self.context = context
            _browser = StateObject(wrappedValue: FileBrowser(context: context))
        }

        var busy: Bool { browser.busy }

        var body: some View {
            PageScaffold(
                scrolls: false,
                primary: ToolbarAction(
                    "Download",
                    systemImage: "arrow.down.doc",
                    primary: true,
                    isEnabled: !browser.selection.isEmpty && browser.ready
                ) {
                    browser.download(browser.selectedFiles)
                }
            ) {
                ToolbarAction("Back", systemImage: "chevron.left") { context.goBack() }
                    .disabled(!context.canGoBack || busy || !context.connected)
                ToolbarAction("Forward", systemImage: "chevron.right") { context.goForward() }
                    .disabled(!context.canGoForward || busy || !context.connected)
                ToolbarAction("Enclosing Folder", systemImage: "arrow.up") { browser.goUp() }
                    .disabled(!browser.canGoUp || busy || !context.connected)
                ToolbarAction("Go to Folder", systemImage: "arrow.turn.down.right") { browser.ask(.goTo) }
                    .disabled(busy || !context.connected)
            } trailing: {
                ToolbarAction("Reload", systemImage: "arrow.clockwise") { context.loadCurrentFileList() }
                    .disabled(busy || !context.connected)
                ToolbarAction("New Folder", systemImage: "folder.badge.plus") { browser.ask(.newFolder) }
                    .disabled(busy || !context.connected)
                ToolbarAction("Upload", systemImage: "arrow.up.doc") { upload() }
                    .disabled(busy || !context.connected)
                ToolbarAction("Close Files", systemImage: "xmark") {
                    FileTransferSessionActions.close(context)
                }
            } header: {
                VStack(alignment: .leading, spacing: RX.Space.s2) {
                    PageTitle(redaction == .all ? "File Transfer" : "\(context.machine.name)", subtitle: "\(subtitle)")
                    HStack(spacing: RX.Space.s3) {
                        FolderBreadcrumb(url: context.currentUrl) { path in
                            context.navigate(path: path)
                        }
                        .disabled(busy || !context.connected)
                        Spacer(minLength: RX.Space.s2)
                        // In the page, not the toolbar: this page stays mounted while
                        // hidden, and a toolbar search field would stay with it.
                        RXSearchField("Filter this folder", text: $browser.filter, width: 200)
                    }
                }
            } content: {
                VStack(spacing: RX.Space.s4) {
                    if context.destroyedSession || (!context.connected && !context.processConnection) {
                        EmptyStateView(
                            "Connection closed",
                            systemImage: "bolt.horizontal",
                            message: context.connectionPhase == .closed ? nil : "\(context.currentHint)",
                            actionTitle: context.destroyedSession ? nil : "Reconnect"
                        ) {
                            context.processBootstrap()
                        }
                        .rxCard()
                        Spacer()
                    } else if context.processConnection, context.currentFileList.isEmpty {
                        VStack(spacing: RX.Space.s3) {
                            ProgressView()
                                .rxSpinner()
                            Text(context.currentHint.isEmpty ? "Connecting…" : "\(context.currentHint)")
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
                        TransferCard(context: context)
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: browser.upload(dropped:))
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
            .focusedSceneValue(\.fileBrowserCommands, browser.commands)
            .sheet(item: $browser.prompt) { prompt in
                FilePromptSheet(prompt: prompt, browser: browser) { browser.prompt = nil }
            }
            // The mouse's back and forward buttons, and a swipe, step through
            // the folders while this page is on screen.
            .onAppear { pointerHistory.update(active: true, context: context) }
            .onDisappear { pointerHistory.update(active: false, context: context) }
            #if DEBUG
                .onReceive(NotificationCenter.default.publisher(for: .benchFiles)) { note in
                    if let index = note.userInfo?["select"] as? Int, browser.files.indices.contains(index) { browser.selection = [browser.files[index].id] }
                    if let text = note.userInfo?["filter"] as? String { browser.filter = text }
                }
            #endif
                .serverToolSwitcher(machine: context.machine.id, current: .files)
        }

        var subtitle: String {
            redaction == .none ? context.machine.getCommand(insertLeadingSSH: false) : ""
        }

        // MARK: Table

        var fileTable: some View {
            VStack(spacing: 0) {
                if browser.files.isEmpty {
                    EmptyStateView(
                        browser.filter.isEmpty ? "Empty folder" : "No matches",
                        systemImage: "folder",
                        message: ""
                    )
                    Spacer(minLength: 0)
                } else {
                    FileTable(browser: browser)
                    // The Table's NSTableView takes drags over its rows before
                    // the page's drop area sees them.
                    .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: browser.upload(dropped:))
                }
            }
            .padding(RX.Space.s2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.clear.rxCard(padding: 0))
            .disabled(busy)
            .opacity(busy ? 0.6 : 1)
        }

        func upload() {
            OpenPanel.present(
                message: "Upload to \(context.currentDir)",
                prompt: "Upload",
                directory: nil,
                canChooseFiles: true,
                canChooseDirectories: true,
                allowsMultipleSelection: true,
                canCreateDirectories: false,
                showsHiddenFiles: false
            ) { urls in
                if !urls.isEmpty { context.upload(urls: urls) }
            }
        }
    }

    /// Watches the window's events for the mouse's back and forward buttons and
    /// for a swipe, while a Files page is shown, and steps through its folders.
    @MainActor
    private final class FolderHistoryPointer {
        private var monitor: Any?

        func update(active: Bool, context: FileTransferContext) {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard active else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .swipe]) { [weak context] event in
                guard let context, Self.handle(event, context: context) else { return event }
                return nil
            }
        }

        /// Steps back or forward for the event; false when it is not one for Files.
        private static func handle(_ event: NSEvent, context: FileTransferContext) -> Bool {
            guard let window = event.window,
                  MainWindow.ordinaryWindows.contains(window),
                  !MainWindow.isShowingSheetOrModal
            else { return false }
            let back: Bool
            switch event.type {
            case .otherMouseDown where event.buttonNumber == 3:
                back = true
            case .otherMouseDown where event.buttonNumber == 4:
                back = false
            case .swipe where event.deltaX != 0:
                // As in Safari and Finder: a swipe to the right goes back.
                back = event.deltaX > 0
            default:
                return false
            }
            guard context.connected, !context.processConnection, !context.isProgressRunning else { return true }
            if back { context.goBack() } else { context.goForward() }
            return true
        }
    }

    // MARK: - Prompts

    /// Go to Folder, New Folder and Rename as small sheets.
    private struct FilePromptSheet: View {
        let prompt: FilePrompt
        @ObservedObject var browser: FileBrowser
        let close: () -> Void

        @State private var text = ""

        var error: String? { browser.problem(with: text, for: prompt) }

        var body: some View {
            SheetScaffold(prompt.title) {
                RXField(prompt.label, error: error) {
                    TextField(String(localized: prompt.placeholder), text: $text)
                        .textFieldStyle(.roundedBorder)
                        .font(prompt.isPath ? .rxCode : .rxBody)
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
            .onAppear { text = browser.initialText(for: prompt) }
        }

        func confirm() {
            guard !text.isEmpty, error == nil else { return }
            browser.perform(prompt, with: text)
            close()
        }
    }

    /// Bridges RayonModule's shared file-transfer core to the Mac app's UI.
    /// RayonModule calls it on the main thread.
    @MainActor
    final class MacFileTransferUIHandler: @preconcurrency FileTransferUIHandler {
        func presentError(_ message: String) {
            Indicator.error(message)
        }

        func requiresConfirmation(_ message: String, completion: @escaping (Bool) -> Void) {
            Indicator.confirm(message: "\(message)", confirmation: completion)
        }

        func autoOpenInterface(_ context: FileTransferContext) {
            if AppRouter.shared.route == .editor(context.id) { return }
            AppRouter.shared.route = .transfer(context.id)
        }
    }

#endif
