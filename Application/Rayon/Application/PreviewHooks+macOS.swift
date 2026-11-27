//
//  PreviewHooks+macOS.swift
//  Rayon
//
//  Debug builds read RAYON_PREVIEW_* from the environment at launch and open
//  the page, sample data or menu-bar item they name, for screenshots and QA
//  without input.
//

#if os(macOS) && DEBUG
    import AppKit
    import RayonModule
    import RayonTerminal
    import SwiftUI

    extension AppDelegate {
        func runPreviewHooks() {
            if ProcessInfo.processInfo.environment["RAYON_PREVIEW_TERMINAL"] != nil,
               let command = SSHCommandReader(command: "ssh demo@203.0.113.10")
            {
                AppRouter.shared.openTerminal(command: command)
                AppRouter.shared.route = .terminal(TerminalManager.shared.sessionContexts.last!.id)
            }
            if let categories = ProcessInfo.processInfo.environment["RAYON_PREVIEW_SETTINGS"]?.split(separator: ",").map(String.init) {
                for (index, category) in categories.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(index) * 2) {
                        if category == "@terminal", let session = TerminalManager.shared.sessionContexts.last {
                            AppRouter.shared.route = .terminal(session.id)
                        } else {
                            AppRouter.shared.openSettings(category)
                        }
                    }
                }
            }
            if let pair = ProcessInfo.processInfo.environment["RAYON_PREVIEW_EDIT"]?.split(separator: "=", maxSplits: 1).map(String.init), pair.count == 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    let old = ConfigBenchmark.value(pair[0])
                    ConfigBenchmark.edit(pair[0], pair[1])
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { ConfigBenchmark.edit(pair[0], old) }
                }
            }
            if ProcessInfo.processInfo.environment["RAYON_PREVIEW_MENUBAR"] != nil {
                MenubarTool.shared.showPreview()
            }
            Bench.runIfRequested()
            if let page = ProcessInfo.processInfo.environment["RAYON_PREVIEW_ROUTE"] {
                let routes: [String: Route] = ["servers": .servers, "desktops": .desktops, "home": .home, "dashboard": .dashboard]
                if let route = routes[page] { AppRouter.shared.route = route }
            }
            if let path = ProcessInfo.processInfo.environment["RAYON_PREVIEW_UU_SESSION"] {
                let open = ProcessInfo.processInfo.environment["RAYON_PREVIEW_OPEN"]?.split(separator: ":", maxSplits: 1).map(String.init)
                Task { @MainActor in
                    await UURemoteAccount.shared.adoptSessionForPreview(from: URL(fileURLWithPath: path))
                    guard let open, open.count == 2,
                          let machine = RayonStore.shared.machines.first(where: { machine in
                              machine.isUURemoteDevice && machine.name == open[1]
                                  && UURemoteAccount.shared.devices.contains { $0.deviceID == machine.uuDeviceID }
                          })
                    else { return }
                    if open[0] == "terminal" { AppRouter.shared.openTerminal(machine: machine.id) }
                    if open[0] == "desktop" { AppRouter.shared.openDesktop(machine: machine.id) }
                }
            }
            if ProcessInfo.processInfo.environment["RAYON_PREVIEW_UU_SIGNIN"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { FolderActions.linkUURemote() }
            }
            if ProcessInfo.processInfo.environment["RAYON_PREVIEW_FOLDERS"] != nil {
                let store = RayonStore.shared
                if store.folder(named: "Lab") == nil { store.createFolder(named: "Lab") }
                let folder = store.folders.first { $0.isLinked }
                    ?? store.createFolder(named: "UU Remote", source: .uuRemote(userID: "preview"))
                var devices: [UUDeviceInfo] = []
                for (id, alias, platform) in [("preview-mac", "Macbook_Pro_M2", 4), ("preview-pc", "Studio PC", 1)] {
                    var device = UUDeviceInfo()
                    device.deviceID = id
                    device.alias = alias
                    device.platform = platform
                    devices.append(device)
                }
                let changes = UURemoteFolderSync.changes(devices: devices, folder: folder.id, machines: store.machines)
                changes.save.forEach { store.save($0) }
                store.deleteMachines(changes.delete)
            }
            if ProcessInfo.processInfo.environment["RAYON_PREVIEW_EDITOR"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { AppRouter.shared.showEditorPreview() }
            }
        }
    }
#endif
