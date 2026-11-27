//
//  FileTransferContext.swift
//  RayonModule
//
//  Shared SFTP session context, previously duplicated between the
//  macOS and iOS apps. Platform-specific UI is delegated through
//  FileTransferInterface.
//

import os
import RayonSSH
import SwiftUI
import Logger
import UniformTypeIdentifiers

/// The session's state lives on the main actor, like the interface showing
/// it; each operation awaits the SFTP session off it.
@MainActor
public class FileTransferContext: ObservableObject, Identifiable, Equatable {
    public nonisolated let id = UUID()

    public var navigationTitle: String {
        machine.name
    }

    @Published public var navigationSubtitle: String = ""

    public let machine: RDMachine
    public let identity: RDIdentity?
    public var firstConnect: Bool = true
    public var destroyedSession: Bool = false {
        didSet {
            if destroyedSession { disconnect() }
        }
    }

    /// The SFTP session and the operation running on it. Operations run one
    /// after another, each waiting for the one before.
    struct Session {
        var lease: SSHLease?
        var sftp: SFTPSession?
        var last: Task<Void, Never>?
        var current: Task<Void, Never>?
    }

    var session = Session()

    @Published public var connected: Bool = false
    @Published public var processConnection: Bool = false

    public enum ConnectionPhase: Sendable {
        case idle
        case connecting
        case connected
        case closed
    }

    @Published public private(set) var connectionPhase: ConnectionPhase = .idle

    @Published public var currentDir: String = "/" {
        didSet {
            navigationSubtitle = currentDir
        }
    }

    @Published public var currentFileList: [RemoteFile] = []
    public var currentUrl: URL {
        URL(fileURLWithPath: currentDir)
    }

    @Published public var isProgressRunning: Bool = true

    @Published public var totalProgress: Progress = .init()
    @Published public var currentProcessingFile: String = ""
    @Published public var currentProgress: Progress = .init()
    @Published public var currentHint: String = ""
    @Published public var currentSpeed: Int = 0
    @Published public var currentProgressCancelable = false
    public var continueCurrentProgress = false {
        didSet {
            // Stopping a transfer cancels it between two chunks.
            if !continueCurrentProgress { session.current?.cancel() }
        }
    }

    public struct RemoteFile: Identifiable, Equatable, Hashable, Sendable {
        /// The file's path: a reload keeps a chosen file chosen while its
        /// size or date changes.
        public var id: URL { url }
        public let base: URL
        public let name: String
        public let url: URL
        /// The entry itself; for a link, the link.
        public let fstat: SFTPEntry
        /// What a link points to; nil for anything else, and for a link
        /// that is broken or loops.
        public let linkTarget: SFTPEntry?
        /// The kind as Finder names it, read once: sorting by kind compares
        /// it many times.
        public let kind: String

        public init(base: URL, name: String, fstat: SFTPEntry, linkTarget: SFTPEntry? = nil) {
            self.base = base
            self.name = name
            url = base.appendingPathComponent(name)
            self.fstat = fstat
            self.linkTarget = linkTarget
            let type: UTType = if fstat.isDirectory || linkTarget?.isDirectory == true {
                .folder
            } else if fstat.isLink, linkTarget == nil {
                .symbolicLink
            } else {
                UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
            }
            // The system names kinds in lower case ("folder"); Finder's column starts them upper case.
            let description = type.localizedDescription ?? UTType.data.localizedDescription ?? ""
            kind = description.prefix(1).localizedUppercase + description.dropFirst()
        }

        /// A folder, or a link to one: it opens by browsing into it.
        public var isFolder: Bool { fstat.isDirectory || linkTarget?.isDirectory == true }
    }

    // MARK: SHELL CONTEXT -

    public init(machine: RDMachine, identity: RDIdentity? = nil) {
        self.machine = machine
        self.identity = identity
        currentDir = machine.fileTransferLoginPath
        processBootstrap()
    }

    public nonisolated static func == (lhs: FileTransferContext, rhs: FileTransferContext) -> Bool {
        lhs.id == rhs.id
    }

    public func putInformation(_ str: String) {
        currentHint = str
    }

    public func processBootstrap() {
        if firstConnect {
            firstConnect = false
            if AppSettings.showsSessionOnConnect.value {
                FileTransferInterface.uiHandler.autoOpenInterface(self)
            }
        }
        enqueue(needsSession: false) { _ in
            await self.connect()
        }
    }

    private func connect() async {
        putInformation(String(localized: "Connecting...", bundle: .module))
        processConnection = true
        connectionPhase = .connecting
        defer { processConnection = false }

        Logger.network.infoFile("sftp session \(id) connecting to \(machine.id)")
        let lease: SSHLease
        let sftp: SFTPSession
        do {
            lease = try await SSHConnectionPool.shared.lease(for: machine) { [weak self] hint in
                Task { @MainActor in self?.putInformation(hint) }
            }
        } catch {
            putInformation(error.localizedDescription)
            processShutdown()
            return
        }
        do {
            sftp = try await lease.connection.openSFTP()
        } catch {
            lease.release()
            putInformation(String(localized: "Failed to setup file transfer protocol", bundle: .module))
            processShutdown()
            return
        }
        let replaced = (session.lease, session.sftp)
        session.lease = lease
        session.sftp = sftp
        await replaced.1?.close()
        replaced.0?.release()

        Logger.network.infoFile("sftp session \(id) connected")
        connected = true
        connectionPhase = .connected
        loadCurrentFileList()
    }

    public func processShutdown() {
        putInformation(String(localized: "Connection Closed", bundle: .module))
        connected = false
        currentFileList = []
        processConnection = false
        isProgressRunning = false
        connectionPhase = .closed
        disconnect()
    }

    private func disconnect() {
        let (lease, sftp, current) = (session.lease, session.sftp, session.current)
        session.lease = nil
        session.sftp = nil
        current?.cancel()
        Task {
            await sftp?.close()
            lease?.release()
        }
    }

    /// Runs `operation` after the ones queued before it. One that needs the
    /// SFTP session is skipped, and the session ended, when it has dropped.
    func enqueue(needsSession: Bool = true, _ operation: @escaping @MainActor (SFTPSession?) async -> Void) {
        let previous = session.last
        session.last = Task {
            await previous?.value
            let sftp = self.session.sftp
            if needsSession {
                guard let sftp, sftp.isActive else {
                    if sftp != nil || self.connected { self.processShutdown() }
                    return
                }
            }
            let current = Task { await operation(sftp) }
            self.session.current = current
            await current.value
        }
    }

    /// The live SFTP session; nil, after ending the session, when it dropped.
    public func connectionAvailableCheckPassed() -> Bool {
        guard let sftp = session.sftp, sftp.isActive else {
            processShutdown()
            return false
        }
        resetCurrentProgress()
        return true
    }

    func resetCurrentProgress() {
        totalProgress = .init()
        currentProcessingFile = ""
        currentProgress = .init()
        currentHint = ""
        currentSpeed = 0
        currentProgressCancelable = false
    }

    private func report(_ error: Error, _ fallback: String) {
        let message = Self.describe(error, fallback)
        FileTransferInterface.uiHandler.presentError(message)
        Logger.network.errorFile("sftp session \(id): \(error) \(private: message)")
    }

    nonisolated static func describe(_ error: Error, _ fallback: String) -> String {
        if error is CancellationError { return String(localized: "Cancelled", bundle: .module) }
        return String(localized: "\(fallback): \(SFTPSession.describe(error))", bundle: .module)
    }

    /// SFTP reports progress from its own threads.
    private nonisolated func reportProgress(_ progress: SFTPProgress) {
        Task { @MainActor in
            let current = Progress(totalUnitCount: max(progress.total, 1))
            current.completedUnitCount = progress.completed
            self.currentProcessingFile = progress.file
            self.currentProgress = current
            self.currentSpeed = progress.bytesPerSecond
        }
    }

    public func loadCurrentFileList() {
        guard connectionAvailableCheckPassed() else { return }
        let currentDir = currentDir
        let currentUrl = currentUrl
        enqueue { [self] sftp in
            putInformation(String(localized: "Loading... \(currentDir)", bundle: .module))
            self.isProgressRunning = true
            let entries: [SFTPEntry]
            do {
                entries = try await sftp?.entries(at: currentDir) ?? []
            } catch {
                entries = []
                report(error, String(localized: "Failed to list \(currentDir)", bundle: .module))
            }
            let targets = await Self.linkTargets(of: entries, in: currentDir, sftp: sftp)
            let builder = entries.map { RemoteFile(base: currentUrl, name: $0.name, fstat: $0, linkTarget: targets[$0.name]) }
            putInformation(String(localized: "Load Complete", bundle: .module))
            guard self.currentDir == currentDir else { return }
            isProgressRunning = false
            currentFileList = builder
        }
    }

    /// What each link in a listing points to, asked for all at once. A
    /// link that loops fails to resolve on the server and stays a link.
    private nonisolated static func linkTargets(of entries: [SFTPEntry], in directory: String, sftp: SFTPSession?) async -> [String: SFTPEntry] {
        guard let sftp else { return [:] }
        return await withTaskGroup(of: (String, SFTPEntry?).self) { group in
            for entry in entries where entry.isLink {
                let path = (directory as NSString).appendingPathComponent(entry.name)
                group.addTask { (entry.name, try? await sftp.entry(at: path)) }
            }
            var targets: [String: SFTPEntry] = [:]
            for await (name, target) in group {
                targets[name] = target
            }
            return targets
        }
    }

    public func createFolder(with name: String) {
        guard connectionAvailableCheckPassed() else { return }
        let url = currentUrl.appendingPathComponent(name)
        enqueue { [self] sftp in
            putInformation(String(localized: "Creating Folder \(url.path)...", bundle: .module))
            self.isProgressRunning = true
            do {
                try await sftp?.createDirectory(at: url.path)
                putInformation(String(localized: "Folder Created", bundle: .module))
            } catch {
                report(error, String(localized: "Failed to create folder", bundle: .module))
            }
            self.loadCurrentFileList()
        }
    }

    /// The folders shown before and after this one, for Back and Forward.
    @Published public private(set) var history = FolderHistory()

    public var canGoBack: Bool { history.canGoBack }
    public var canGoForward: Bool { history.canGoForward }

    public func navigate(path: String) {
        guard connectionAvailableCheckPassed() else { return }
        history.visit(from: currentDir, to: path)
        currentDir = path
        loadCurrentFileList()
    }

    /// Shows the folder shown before this one.
    public func goBack() {
        guard canGoBack, connectionAvailableCheckPassed(),
              let path = history.goBack(from: currentDir)
        else { return }
        currentDir = path
        loadCurrentFileList()
    }

    /// Shows the folder that Back left.
    public func goForward() {
        guard canGoForward, connectionAvailableCheckPassed(),
              let path = history.goForward(from: currentDir)
        else { return }
        currentDir = path
        loadCurrentFileList()
    }

    public func upload(urls: [URL]) {
        guard connectionAvailableCheckPassed() else { return }
        Telemetry.record(.feature(.fileTransfers))
        let base = currentUrl
        continueCurrentProgress = true
        enqueue { [self] sftp in
            self.isProgressRunning = true
            self.currentProgressCancelable = true
            putInformation(String(localized: "Uploading...", bundle: .module))
            for (current, url) in urls.enumerated() {
                let progress = Progress(totalUnitCount: Int64(urls.count))
                progress.completedUnitCount = Int64(current)
                totalProgress = progress
                do {
                    try await sftp?.upload(url, toDirectory: base.path) { [weak self] in self?.reportProgress($0) }
                } catch {
                    report(error, String(localized: "Upload failed", bundle: .module))
                    break
                }
            }
            putInformation(String(localized: "Upload Completed", bundle: .module))
            self.loadCurrentFileList()
        }
    }

    public func rename(from: URL, to: URL) {
        guard connectionAvailableCheckPassed() else { return }
        enqueue { [self] sftp in
            putInformation(String(localized: "Renaming...", bundle: .module))
            self.isProgressRunning = true
            do {
                try await sftp?.rename(from.path, to: to.path)
                putInformation(String(localized: "Renamed Successfully", bundle: .module))
            } catch {
                report(error, String(localized: "Failed to rename", bundle: .module))
            }
            self.loadCurrentFileList()
        }
    }

    /// Deletes the items one after another, folders with all they hold;
    /// the first that fails stops the rest.
    public func delete(items: [URL]) {
        guard !items.isEmpty, connectionAvailableCheckPassed() else { return }
        continueCurrentProgress = true
        enqueue { [self] sftp in
            self.isProgressRunning = true
            self.currentProgressCancelable = true
            putInformation(String(localized: "Deleting...", bundle: .module))
            do {
                for (index, item) in items.enumerated() {
                    try Task.checkCancellation()
                    totalProgress = Self.progress(index, of: items.count)
                    currentProcessingFile = item.path
                    try await sftp?.removeItem(at: item.path) { [weak self] file in
                        Task { @MainActor in self?.currentProcessingFile = file }
                    }
                }
                putInformation(String(localized: "Delete Completed", bundle: .module))
            } catch {
                report(error, String(localized: "Delete failed", bundle: .module))
            }
            self.loadCurrentFileList()
        }
    }

    /// Downloads the items into `toDir`, each under a name not taken there.
    public func download(from items: [URL], toDir: URL) {
        guard !items.isEmpty else { return }
        Telemetry.record(.feature(.fileTransfers))
        guard connectionAvailableCheckPassed() else { return }
        continueCurrentProgress = true
        enqueue { [self] sftp in
            self.isProgressRunning = true
            self.currentProgressCancelable = true
            putInformation(String(localized: "Downloading...", bundle: .module))
            do {
                for (index, item) in items.enumerated() {
                    try Task.checkCancellation()
                    totalProgress = Self.progress(index, of: items.count)
                    let destination = Self.freeDestination(for: item, in: toDir)
                    try await sftp?.download(item.path, to: destination) { [weak self] in self?.reportProgress($0) }
                }
                putInformation(String(localized: "Download Completed", bundle: .module))
                FileTransferInterface.uiHandler.downloadCompleted()
            } catch {
                report(error, String(localized: "Download failed", bundle: .module))
            }
            self.loadCurrentFileList()
        }
    }

    private nonisolated static func progress(_ completed: Int, of total: Int) -> Progress {
        let progress = Progress(totalUnitCount: Int64(total))
        progress.completedUnitCount = Int64(completed)
        return progress
    }

    /// `item`'s name in `folder`, or "name.2.ext", "name.3.ext"… when taken.
    nonisolated static func freeDestination(for item: URL, in folder: URL) -> URL {
        let base = folder.appendingPathComponent(item.lastPathComponent)
        let ext = base.pathExtension
        var candidate = base
        var duplicate = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            duplicate += 1
            var path = base.deletingPathExtension().path + ".\(duplicate)"
            if !ext.isEmpty { path += ".\(ext)" }
            candidate = URL(fileURLWithPath: path)
        }
        return candidate
    }
}
