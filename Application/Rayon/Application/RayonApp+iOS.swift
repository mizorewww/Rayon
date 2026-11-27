//
//  RayonApp+iOS.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/3/2.
//

#if os(iOS)
import RayonModule
import SwiftUI
import RayonTerminal

@main
struct mRayonApp: App {
    @StateObject private var store = RayonStore.shared

    init() {
        #if DEBUG
            Logger.app.debugFile("command arguments: \(CommandLine.arguments.joined(separator: " "))")
        #endif

        // Shared file-transfer core lives in RayonModule; register the
        // platform UI handler it delegates to.
        FileTransferInterface.uiHandler = IOSFileTransferUIHandler()
        TerminalInterface.uiHandler = IOSTerminalUIHandler()
        HostKeyTrust.handler = IOSHostKeyTrustHandler()

        _ = RayonStore.shared
        CloudSyncModel.shared.start()

        Logger.app.infoFile("launched")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onOpenURL { url in
                    // uuremote:// external integration callbacks arrive on
                    // the app's own rayon:// scheme.
                    UULocalBridge.handleCallback(url)
                }
                #if DEBUG
                .fullScreenCover(isPresented: .constant(ProcessInfo.processInfo.environment["RAYON_PREVIEW_EDITOR"] != nil)) {
                    EditorPreviewScreen()
                }
                #endif
                .onAppear {
                    AppearancePreference.applyStored()
                    RayonTerminalView.setCopyOnSelect(store.terminalCopyOnSelect)
                    RayonTerminalView.setClipboardSharing(store.terminalClipboardSharing)
                    checkAgreement()
                    if let problem = store.launchProblem {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { UIBridge.presentAlert(with: problem) }
                    }
                    #if DEBUG
                        seedPreviewServers()
                        seedPreviewVNC()
                        openPreviewTool()
                    #endif
                }
                .onChange(of: store.licenseAgreed) { _ in
                    checkAgreement()
                }
        }
    }

    #if DEBUG
        /// `RAYON_PREVIEW_SEED=1` adds sample UU Remote devices, enough
        /// servers for lists that scroll under the bars.
        func seedPreviewServers() {
            guard ProcessInfo.processInfo.environment["RAYON_PREVIEW_SEED"] != nil else { return }
            // A folder of its own: syncing devices into a signed-in
            // account's folder would drop that account's real devices.
            let preview = RDFolder.Source.uuRemote(userID: "preview")
            let folder = store.folders.first { $0.source == preview }
                ?? store.createFolder(named: "UU Remote Preview", source: preview)
            let devices = (1 ... 16).map { index -> UUDeviceInfo in
                var device = UUDeviceInfo()
                device.deviceID = "preview-\(index)"
                device.alias = index.isMultiple(of: 2) ? "Studio PC \(index)" : "MacBook Pro \(index)"
                device.platform = index.isMultiple(of: 2) ? 1 : 4
                return device
            }
            let changes = UURemoteFolderSync.changes(devices: devices, folder: folder.id, machines: store.machines)
            changes.save.forEach { store.save($0) }
            store.deleteMachines(changes.delete)
        }

        /// `RAYON_PREVIEW_VNC=<port>` adds a "Preview VNC" server, a VNC
        /// screen at 127.0.0.1 on that port (the Mac, from the simulator).
        static let previewVNCID = UUID(uuidString: "C0FFEE00-0000-4000-8000-00000000F00D")!

        func seedPreviewVNC() {
            guard let port = ProcessInfo.processInfo.environment["RAYON_PREVIEW_VNC"] else { return }
            var machine = RDMachine(id: Self.previewVNCID, remoteAddress: "127.0.0.1", remotePort: "22", name: "Preview VNC")
            machine.remoteDesktopProtocol = .vnc
            machine.vncPort = port
            store.save(machine)
        }

        /// `RAYON_PREVIEW_TOOL=terminal|files|monitor|desktop` opens the
        /// first server's page on that tool (for a desktop, Preview VNC or
        /// the first server with one), for screenshots without input.
        func openPreviewTool() {
            let machines = store.machines
            guard let name = ProcessInfo.processInfo.environment["RAYON_PREVIEW_TOOL"],
                  let tool = ServerTool.allCases.first(where: { $0.title.lowercased() == name }),
                  let machine = tool == .desktop
                  ? machines.first(where: { $0.id == Self.previewVNCID }) ?? machines.first(where: \.hasRemoteDesktop)
                  : machines.first
            else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                tool.open(machine.id)
                SessionNavigation.shared.reveal(.server(machine.id), tool: tool)
            }
        }
    #endif

    func checkAgreement() {
        guard !store.licenseAgreed else {
            return
        }
        let host = UIHostingController(rootView: AgreementView().rxSolidBars())
        host.preferredContentSize = preferredPopOverSize
        host.isModalInPresentation = true
        host.modalTransitionStyle = .coverVertical
        host.modalPresentationStyle = .formSheet
        // At launch the window is not in the hierarchy yet; the queue
        // replays the present once it is.
        PresentationQueue.present(next: host)
    }
}

#endif
