//
//  ServerActions.swift
//  Rayon
//
//  What can be done to saved servers, the same on every platform; opening
//  their tools and their editor is in ServerActions+macOS / +iOS.
//

import MachineStatusView
import RayonModule
import SwiftUI

@MainActor
enum ServerActions {
    static func duplicate(_ machine: RDMachine.ID) {
        guard var copy = RayonStore.shared.machine(machine) else { return }
        copy.id = UUID()
        copy.name = String(localized: "\(copy.name) copy")
        RayonStore.shared.save(copy)
    }

    /// Asks, then deletes the servers and ends their monitors.
    static func delete(_ machines: [RDMachine.ID], onDeleted: (() -> Void)? = nil) {
        let store = RayonStore.shared
        guard !machines.isEmpty else { return }
        let message: LocalizedStringResource = machines.count == 1
            ? (store.machine(machines[0]).map { "Delete \($0.name)?" } ?? "Delete this server?")
            : "Delete \(machines.count) servers?"
        let informative: LocalizedStringResource
        if machines.contains(where: { store.machine($0)?.isUURemoteDevice == true }) {
            informative = "Port forwards through it stop working. A UU Remote device stays on your UU Remote account, which Rayon cannot remove it from; Rayon stops listing it."
        } else {
            informative = "Port forwards through it stop working."
        }
        Indicator.confirm(
            message: message,
            informative: informative,
            confirmTitle: "Delete",
            destructive: true
        ) { confirmed in
            guard confirmed else { return }
            UURemoteAccount.shared.forgetDevices(ofDeleting: machines)
            for machine in machines {
                if let session = MonitorCenter.shared.session(for: machine) {
                    MonitorCenter.shared.end(session.id)
                }
            }
            store.deleteMachines(machines)
            store.cleanRecentIfNeeded()
            onDeleted?()
        }
    }

    /// For a server whose keys were replaced: its next host key is saved.
    static func forgetHostKey(_ machine: RDMachine.ID) {
        guard let read = RayonStore.shared.machine(machine) else { return }
        Indicator.confirm(
            message: "Forget the host key of \(read.name)?",
            informative: "The key the server presents on the next connection is saved as its key. Do this only when you know its keys were replaced.",
            confirmTitle: "Forget"
        ) { confirmed in
            guard confirmed else { return }
            read.forgetHostKey()
        }
    }

    /// The next terminal checks the server for Ghostty's terminfo again and
    /// installs it if it is missing (say, after ~/.terminfo was cleared).
    static func reinstallTerminfo(_ machine: RDMachine.ID) {
        RayonStore.shared.updateMachine(machine) { $0.forgetGhosttyTerminfo() }
    }

    static func copyAddress(_ machine: RDMachine.ID) {
        guard let read = RayonStore.shared.machine(machine) else { return }
        Pasteboard.copy("\(read.remoteAddress):\(read.remotePort)")
    }

    static func copyCommand(_ machine: RDMachine.ID) {
        guard let read = RayonStore.shared.machine(machine) else { return }
        Pasteboard.copy(read.getCommand { RayonStore.shared.machine($0) })
    }
}

/// Open a tool (Mac: also New Terminal, View Desktop Only, Show in Menu
/// Bar; iPhone and iPad: UU Remote in picture in picture); Edit, Move to
/// Folder, Duplicate; Copy Address (a UU device's id), Copy SSH Command,
/// Forget Host Key, Check Terminfo Again; Delete.
struct ServerContextMenu: View {
    let machine: RDMachine.ID
    /// False where the tools already sit beside the menu (a tile's ⋯ button).
    var includesTools = true

    var body: some View {
        let read = RayonStore.shared.machine(machine) ?? RDMachine()
        Section {
            if includesTools {
                ForEach(ServerTool.available(for: read)) { tool in
                    Button(tool.openTitle, systemImage: tool.systemImage) { tool.show(machine) }
                }
            }
            #if os(macOS)
                if includesTools, read.hasRemoteDesktop {
                    Button("View Desktop Only", systemImage: "eye") {
                        AppRouter.shared.openDesktop(machine: machine, viewOnly: true)
                    }
                }
                Button("New Terminal", systemImage: "plus.rectangle") {
                    AppRouter.shared.openTerminal(machine: machine)
                }
                Button("Show in Menu Bar", systemImage: "menubar.rectangle") {
                    AppRouter.shared.showInMenuBar(machine: machine)
                }
            #else
                if read.remoteDesktopProtocol == .uuRemote, UULocalBridge.officialAppInstalled {
                    Button("UU Remote (PiP)", systemImage: "pip") {
                        UULocalBridge.openControlInOfficialApp(for: read)
                    }
                }
            #endif
        }
        Section {
            Button("Edit…", systemImage: "pencil") { ServerActions.edit(machine) }
            MoveToFolderMenu(machines: [machine])
            Button("Duplicate", systemImage: "plus.square.on.square") { ServerActions.duplicate(machine) }
        }
        Section {
            if read.isUURemoteDevice {
                // Its address is the device id; no ssh command reaches it.
                Button("Copy Device ID", systemImage: "doc.on.doc") { Pasteboard.copy(read.uuDeviceID) }
            } else {
                Button("Copy Address", systemImage: "doc.on.doc") { ServerActions.copyAddress(machine) }
                Button("Copy SSH Command", systemImage: "chevron.left.forwardslash.chevron.right") {
                    ServerActions.copyCommand(machine)
                }
            }
            Button("Forget Host Key…", systemImage: "key.slash") { ServerActions.forgetHostKey(machine) }
            if read.hasGhosttyTerminfo {
                Button("Check Terminfo Again", systemImage: "arrow.triangle.2.circlepath") {
                    ServerActions.reinstallTerminfo(machine)
                }
                .help("On the next terminal, check that the server still has Ghostty's terminfo, and install it if not")
            }
        }
        Section {
            Button("Delete…", systemImage: "trash", role: .destructive) { ServerActions.delete([machine]) }
        }
    }
}

extension ServerTool {
    /// The menu item that opens the tool.
    var openTitle: LocalizedStringResource {
        switch self {
        case .terminal: "Open Terminal"
        case .files: "Open Files"
        case .editor: "Open Editor"
        case .monitor: "Open Monitor"
        case .desktop: "Open Desktop"
        }
    }
}

/// host, or host:port when the port is not 22.
extension RDMachine {
    var displayAddress: String {
        remotePort.isEmpty || remotePort == "22" ? remoteAddress : "\(remoteAddress):\(remotePort)"
    }
}
