//
//  SettingsGroup.swift
//  Rayon
//
//  What Settings is made of: Rayon's own pages (General, Connection, About),
//  each a form of titled groups, and the terminal's categories from
//  RayonTerminal between them. Search finds a Rayon group by its words.
//

import RayonModule
import RayonTerminal
import SwiftUI

enum SettingsPage: Hashable {
    case general
    case connection
    case terminal(TerminalSettingsCategory)
    case about

    /// What the router and preview hooks name it by.
    var id: String {
        switch self {
        case .general: "general"
        case .connection: "connection"
        case let .terminal(category): category.id
        case .about: "about"
        }
    }

    init?(id: String) {
        switch id {
        case "general": self = .general
        case "connection": self = .connection
        case "about": self = .about
        default:
            guard let category = TerminalSettingsCategory.all.first(where: { $0.id == id }) else { return nil }
            self = .terminal(category)
        }
    }

    var title: String {
        switch self {
        case .general: "General"
        case .connection: "Connection"
        case let .terminal(category): category.title
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .connection: "network"
        case let .terminal(category): category.icon
        case .about: "info.circle"
        }
    }

    /// The list, in its sections: Rayon's pages, the terminal's, then About.
    static let sections: [(title: String, pages: [SettingsPage])] = [
        ("Rayon", [.general, .connection]),
        ("Terminal", TerminalSettingsCategory.all.map(SettingsPage.terminal)),
        ("", [.about]),
    ]

    /// Rayon's groups on this page; on a terminal page they come first.
    var groups: [SettingsGroup] {
        SettingsGroup.allCases.filter { $0.page == self && $0.isAvailable }
    }
}

enum SettingsGroup: String, CaseIterable, Identifiable {
    case appearance
    case sessions
    case recent
    case sync
    case data
    case ssh
    case uuRemote
    case monitor
    case terminalClipboard
    case about
    case acknowledgements

    var id: String {
        rawValue
    }

    var page: SettingsPage {
        switch self {
        case .appearance, .sessions, .recent, .sync, .data: .general
        case .ssh, .uuRemote, .monitor: .connection
        case .terminalClipboard: SettingsPage(id: "input") ?? .general
        case .about, .acknowledgements: .about
        }
    }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .sessions: "Sessions"
        case .recent: "Recent"
        case .sync: "iCloud Sync"
        case .data: "Data"
        case .ssh: "SSH"
        case .uuRemote: "NetEase UU Remote"
        case .monitor: "Monitor"
        case .terminalClipboard: "Copy on Select"
        case .about: "Rayon"
        case .acknowledgements: "Acknowledgements"
        }
    }

    /// The words search finds the group by, besides its page and title.
    var keywords: String {
        switch self {
        case .appearance: "appearance dark light mode theme system effects animation background home glow reduce motion"
        case .sessions: "open sessions automatically ask before closing confirmation quit"
        case .recent: "recent servers history quick connect commands record remember"
        case .sync: "icloud sync cloud servers identities snippets port forwards terminal settings credentials devices"
        case .data: "data container files log diagnostics backup export import restore ssh config openssh archive"
        case .ssh: "ssh timeout connect wait host key known hosts fingerprint terminfo ghostty"
        case .uuRemote: "uu remote netease remote desktop device account qr login"
        case .monitor: "monitor refresh interval status"
        case .terminalClipboard: "copy on select selection clipboard pasteboard automatically share remote osc52 programs"
        case .about: "version build license source github issues agreement"
        case .acknowledgements: "acknowledgements credits libraries ghostty"
        }
    }

    /// The iPhone and iPad keep the UU Remote account under More.
    var isAvailable: Bool {
        #if os(macOS)
            true
        #else
            self != .uuRemote
        #endif
    }

    @MainActor @ViewBuilder private var uuRemoteRows: some View {
        #if os(macOS)
            UURemoteSettings()
        #endif
    }

    func matches(_ query: String) -> Bool {
        let text = "\(page.title) \(title) \(keywords)".lowercased()
        return query.lowercased().split(whereSeparator: \.isWhitespace).allSatisfy { text.contains($0) }
    }

    @MainActor @ViewBuilder var rows: some View {
        switch self {
        case .appearance: AppearanceSettings()
        case .sessions: SessionSettings()
        case .recent: RecentSettings()
        case .sync: CloudSyncSettings()
        case .data: DataSettings()
        case .ssh: SSHSettings()
        case .uuRemote: uuRemoteRows
        case .monitor: MonitorSettings()
        case .terminalClipboard: TerminalClipboardSettings()
        case .about: AboutSettings()
        case .acknowledgements: AcknowledgementSettings()
        }
    }
}

/// A group as a form section; `prefix` names its page in search results.
struct SettingsGroupSection: View {
    let group: SettingsGroup
    var prefix: String?

    var body: some View {
        Section(prefix.map { "\($0) › \(group.title)" } ?? group.title) {
            group.rows
        }
    }
}
