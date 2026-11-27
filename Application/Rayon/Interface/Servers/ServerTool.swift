//
//  ServerTool.swift
//  Rayon
//

import RayonModule

/// The five ways into a server. Every surface that opens one (tiles, table rows,
/// context menus, the session switcher, the sidebar) uses these names, symbols and
/// descriptions, so a button means the same thing wherever it appears.
enum ServerTool: CaseIterable, Identifiable {
    case terminal
    case files
    case editor
    case monitor
    case desktop

    var id: Self { self }

    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .files: return "Files"
        case .editor: return "Editor"
        case .monitor: return "Monitor"
        case .desktop: return "Desktop"
        }
    }

    var systemImage: String {
        switch self {
        case .terminal: return "terminal"
        case .files: return "folder"
        case .editor: return "square.and.pencil"
        case .monitor: return "gauge.with.dots.needle.33percent"
        case .desktop: return "display"
        }
    }

    /// Tooltip: what the tool does, in a sentence.
    var help: String {
        switch self {
        case .terminal: return "Open an SSH terminal on this server"
        case .files: return "Browse, upload and download files over SFTP"
        case .editor: return "Edit text files on this server"
        case .monitor: return "Watch CPU, memory, disk and network usage"
        case .desktop: return "Open a VNC or UU Remote desktop"
        }
    }

    /// The tools a server can actually show; a dead-end "Desktop" on a
    /// server without one would only error out. A UU Remote device has them
    /// all: UU is only how it is reached.
    static func available(for machine: RDMachine) -> [ServerTool] {
        allCases.filter { $0 != .desktop || machine.hasRemoteDesktop }
    }

    /// The tooltip for this tool on `machine`.
    func help(for machine: RDMachine) -> String {
        if self == .terminal, machine.isUURemoteDevice { return "Open a terminal session on the device through UU Remote" }
        return help
    }
}
