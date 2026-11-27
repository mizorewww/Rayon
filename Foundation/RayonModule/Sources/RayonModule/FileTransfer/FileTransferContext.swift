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

public class FileTransferContext: ObservableObject, Identifiable, Equatable, @unchecked Sendable {
    public var id: UUID = .init()

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

    let session = OSAllocatedUnfairLock(initialState: Session())

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
    private let progressContinuationLock = NSLock()
    private var progressContinuation = false

    public var continueCurrentProgress: Bool {
        get {
            progressContinuationLock.lock()
            defer { progressContinuationLock.unlock() }
            return progressContinuation
        }
        set {
            progressContinuationLock.lock()
            progressContinuation = newValue
            progressContinuationLock.unlock()
            // Stopping a transfer cancels it between two chunks.
            if !newValue { session.withLock { $0.current }?.cancel() }
        }
    }

    public struct RemoteFile: Identifiable, Equatable, Hashable, Sendable {
        public var id: RemoteFile { self }
        public let base: URL
        public let name: String
        /// The entry itself; for a link, the link.
        public let fstat: SFTPEntry
        /// What a link points to; nil for anything else, and for a link
        /// that is broken or loops.
        public let linkTarget: SFTPEntry?

        public init(base: URL, name: String, fstat: SFTPEntry, linkTarget: SFTPEntry? = nil) {
            self.base = base
            self.name = name
            self.fstat = fstat
            self.linkTarget = linkTarget
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

    public static func == (lhs: FileTransferContext, rhs: FileTransferContext) -> Bool {
        lhs.id == rhs.id
    }

    public func putInformation(_ str: String) {
        onMainThread {
            self.currentHint = str
        }
    }

    public func processBootstrap() {
        onMainThread {
            guard self.firstConnect else { return }
            self.firstConnect = false
            guard MainActor.assumeIsolated({ RayonStore.shared.openInterfaceAutomatically }) else { return }
            FileTransferInterface.uiHandler.autoOpenInterface(self)
        }
        enqueue(needsSession: false) { _ in
            await self.connect()
        }
    }

    private func connect() async {
        putInformation("Connecting...")
        onMainThread {
            self.processConnection = true
            self.connectionPhase = .connecting
        }
        defer { onMainThread { self.processConnection = false } }

        Logger.network.infoFile("sftp session \(id) connecting to \(machine.id)")
        let lease: SSHLease
        let sftp: SFTPSession
        do {
            lease = try await SSHConnectionPool.shared.lease(for: machine) { [weak self] hint in
                self?.putInformation(hint)
            }
        } catch {
            putInformation(error.localizedDescription)
            onMainThread { self.processShutdown() }
            return
        }
        do {
            sftp = try await lease.connection.openSFTP()
        } catch {
            lease.release()
            putInformation("Failed to setup file transfer protocol")
            onMainThread { self.processShutdown() }
            return
        }
        let replaced = session.withLock { state in
            defer { state.lease = lease; state.sftp = sftp }
            return (state.lease, state.sftp)
        }
        await replaced.1?.close()
        replaced.0?.release()

        Logger.network.infoFile("sftp session \(id) connected")
        onMainThread {
            self.connected = true
            self.connectionPhase = .connected
            self.loadCurrentFileList()
        }
    }

    public func processShutdown() {
        putInformation("Connection Closed")
        onMainThread {
            self.connected = false
            self.currentFileList = []
            self.processConnection = false
            self.isProgressRunning = false
            self.connectionPhase = .closed
        }
        disconnect()
    }

    private func disconnect() {
        let (lease, sftp, current) = session.withLock { state in
            defer { state.lease = nil; state.sftp = nil }
            return (state.lease, state.sftp, state.current)
        }
        current?.cancel()
        Task {
            await sftp?.close()
            lease?.release()
        }
    }

    /// Runs `operation` after the ones queued before it. One that needs the
    /// SFTP session is skipped, and the session ended, when it has dropped.
    func enqueue(needsSession: Bool = true, _ operation: @escaping @Sendable (SFTPSession?) async -> Void) {
        session.withLock { state in
            let previous = state.last
            let task = Task {
                await previous?.value
                let sftp = self.session.withLock { $0.sftp }
                if needsSession {
                    guard let sftp, sftp.isActive else {
                        if sftp != nil || self.connected { onMainThread { self.processShutdown() } }
                        return
                    }
                }
                let current = Task { await operation(sftp) }
                self.session.withLock { $0.current = current }
                await current.value
            }
            state.last = task
        }
    }

    /// The live SFTP session; nil, after ending the session, when it dropped.
    public func connectionAvailableCheckPassed() -> Bool {
        guard let sftp = session.withLock({ $0.sftp }), sftp.isActive else {
            processShutdown()
            return false
        }
        resetCurrentProgress()
        return true
    }

    func resetCurrentProgress() {
        onMainThread { [self] in
            totalProgress = .init()
            currentProcessingFile = ""
            currentProgress = .init()
            currentHint = ""
            currentSpeed = 0
            currentProgressCancelable = false
        }
    }

    private func report(_ error: Error, _ fallback: String) {
        let message = Self.describe(error, fallback)
        onMainThread {
            FileTransferInterface.uiHandler.presentError(message)
        }
        Logger.network.errorFile("sftp session \(id): \(message)")
    }

    static func describe(_ error: Error, _ fallback: String) -> String {
        if error is CancellationError { return "Cancelled" }
        return "\(fallback): \(SFTPSession.describe(error))"
    }

    private func reportProgress(_ progress: SFTPProgress) {
        onMainThread {
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
            putInformation("Loading... \(currentDir)")
            onMainThread { self.isProgressRunning = true }
            let entries: [SFTPEntry]
            do {
                entries = try await sftp?.entries(at: currentDir) ?? []
            } catch {
                entries = []
                report(error, "Failed to list \(currentDir)")
            }
            let targets = await Self.linkTargets(of: entries, in: currentDir, sftp: sftp)
            let builder = entries.map { RemoteFile(base: currentUrl, name: $0.name, fstat: $0, linkTarget: targets[$0.name]) }
            putInformation("Load Complete")
            onMainThread {
                guard self.currentDir == currentDir else { return }
                self.isProgressRunning = false
                self.currentFileList = builder
            }
        }
    }

    /// What each link in a listing points to, asked for all at once. A
    /// link that loops fails to resolve on the server and stays a link.
    private static func linkTargets(of entries: [SFTPEntry], in directory: String, sftp: SFTPSession?) async -> [String: SFTPEntry] {
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
            putInformation("Creating Folder \(url.path)...")
            onMainThread { self.isProgressRunning = true }
            do {
                try await sftp?.createDirectory(at: url.path)
                putInformation("Folder Created")
            } catch {
                report(error, "Failed to create folder")
            }
            onMainThread { self.loadCurrentFileList() }
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
        let base = currentUrl
        continueCurrentProgress = true
        enqueue { [self] sftp in
            onMainThread {
                self.isProgressRunning = true
                self.currentProgressCancelable = true
            }
            putInformation("Uploading...")
            for (current, url) in urls.enumerated() {
                onMainThread {
                    let progress = Progress(totalUnitCount: Int64(urls.count))
                    progress.completedUnitCount = Int64(current)
                    self.totalProgress = progress
                }
                do {
                    try await sftp?.upload(url, toDirectory: base.path) { [weak self] in self?.reportProgress($0) }
                } catch {
                    report(error, "Upload failed")
                    break
                }
            }
            putInformation("Upload Completed")
            onMainThread { self.loadCurrentFileList() }
        }
    }

    public func rename(from: URL, to: URL) {
        guard connectionAvailableCheckPassed() else { return }
        enqueue { [self] sftp in
            putInformation("Renaming...")
            onMainThread { self.isProgressRunning = true }
            do {
                try await sftp?.rename(from.path, to: to.path)
                putInformation("Renamed Successfully")
            } catch {
                report(error, "Failed to rename")
            }
            onMainThread { self.loadCurrentFileList() }
        }
    }

    public func delete(item: URL) {
        guard connectionAvailableCheckPassed() else { return }
        continueCurrentProgress = true
        enqueue { [self] sftp in
            onMainThread {
                self.isProgressRunning = true
                self.currentProgressCancelable = true
                self.currentProcessingFile = item.path
            }
            putInformation("Deleting...")
            do {
                try await sftp?.removeItem(at: item.path) { [weak self] file in
                    onMainThread { self?.currentProcessingFile = file }
                }
                putInformation("Delete Completed")
            } catch {
                report(error, "Delete failed")
            }
            onMainThread { self.loadCurrentFileList() }
        }
    }

    public func download(from: URL, toDir: URL) {
        let fromPath = from.path
        var to = toDir.path
        if !to.hasSuffix("/") { to += "/" }
        to += from.lastPathComponent
        let toBase = URL(fileURLWithPath: to)
        let ext = toBase.pathExtension
        var duplicate = 1
        while FileManager.default.fileExists(atPath: to) {
            duplicate += 1
            to = toBase.deletingPathExtension().path + ".\(duplicate)"
            if !ext.isEmpty { to += ".\(ext)" }
        }
        let destination = URL(fileURLWithPath: to)
        guard connectionAvailableCheckPassed() else { return }
        continueCurrentProgress = true
        enqueue { [self] sftp in
            onMainThread {
                self.isProgressRunning = true
                self.currentProgressCancelable = true
            }
            putInformation("Downloading...")
            do {
                try await sftp?.download(fromPath, to: destination) { [weak self] in self?.reportProgress($0) }
                putInformation("Download Completed")
                onMainThread {
                    FileTransferInterface.uiHandler.downloadCompleted()
                }
            } catch {
                report(error, "Download failed")
            }
            onMainThread { self.loadCurrentFileList() }
        }
    }
}
