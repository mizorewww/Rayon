//
//  PreviewHooks+iOS.swift
//  Rayon
//
//  Debug builds read RAYON_PREVIEW_* from the environment at launch and
//  open the tab, sample data or tool they name, for screenshots without
//  input. RAYON_PREVIEW_TAB is read by TabsView, RAYON_PREVIEW_EDITOR by
//  RootView, RAYON_PREVIEW_SETTINGS=<page> by MoreView and SettingsView.
//

#if os(iOS) && DEBUG
    import RayonModule
    import SwiftUI

    extension RootView {
        func runPreviewHooks() {
            seedPreviewServers()
            seedPreviewVNC()
            PreviewSSH.seed()
            openPreviewTool()
            if ProcessInfo.processInfo.environment["RAYON_PREVIEW_SETTINGS"] != nil {
                SessionNavigation.shared.selection = .settings
            }
        }

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
                  let tool = ServerTool.allCases.first(where: { $0.title.key.lowercased() == name }),
                  let machine = tool == .desktop
                  ? machines.first(where: { $0.id == Self.previewVNCID }) ?? machines.first(where: \.hasRemoteDesktop)
                  : machines.first
            else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                tool.open(machine.id)
                SessionNavigation.shared.reveal(.server(machine.id), tool: tool)
            }
        }
    }
#endif
