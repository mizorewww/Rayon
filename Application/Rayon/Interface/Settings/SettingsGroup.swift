//
//  SettingsGroup.swift
//  Rayon
//
//  What Settings is made of: Rayon's own pages (General, Connection, About),
//  each a form of titled groups, and the terminal's categories and their
//  subpages from RayonTerminal between them. Search finds a Rayon group by
//  its words.
//

import RayonModule
import RayonTerminal
import SwiftUI

enum SettingsPage: Hashable {
    case general
    case connection
    case terminal(TerminalSettingsCategory)
    /// A group of a terminal category's settings, opened from its page.
    case terminalSubpage(TerminalSettingsSubpage)
    case about

    /// What the router and preview hooks name it by.
    var id: String {
        switch self {
        case .general: "general"
        case .connection: "connection"
        case let .terminal(category): category.id
        case let .terminalSubpage(subpage): subpage.id
        case .about: "about"
        }
    }

    /// The page the sidebar shows as selected: a subpage's category.
    var sidebarPage: SettingsPage {
        if case let .terminalSubpage(subpage) = self { .terminal(subpage.category) } else { self }
    }

    init?(id: String) {
        switch id {
        case "general": self = .general
        case "connection": self = .connection
        case "about": self = .about
        default:
            if let subpage = TerminalSettingsSubpage(id: id) {
                self = .terminalSubpage(subpage)
            } else if let category = TerminalSettingsCategory.all.first(where: { $0.id == id }) {
                self = .terminal(category)
            } else {
                return nil
            }
        }
    }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .connection: String(localized: "Connection")
        case let .terminal(category): category.title
        case let .terminalSubpage(subpage): subpage.title
        case .about: String(localized: "About")
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .connection: "network"
        case let .terminal(category): category.icon
        case let .terminalSubpage(subpage): subpage.category.icon
        case .about: "info.circle"
        }
    }

    /// Whether the page shows the live terminal preview.
    var previews: Bool {
        switch self {
        case let .terminal(category): category.previews
        case let .terminalSubpage(subpage): subpage.category.previews
        default: false
        }
    }

    /// The list, in its sections: Rayon's pages, the terminal's, then About
    /// on its own, without a title.
    static let sections: [SettingsSection] = [
        SettingsSection(title: "Rayon", pages: [.general, .connection]),
        SettingsSection(title: String(localized: "Terminal"), pages: TerminalSettingsCategory.all.map(SettingsPage.terminal)),
        SettingsSection(title: nil, pages: [.about]),
    ]

    /// Every page, subpages after their category: what the benchmark visits.
    static var all: [SettingsPage] {
        sections.flatMap(\.pages).flatMap { page -> [SettingsPage] in
            guard case let .terminal(category) = page else { return [page] }
            return [page] + category.subpages.map(SettingsPage.terminalSubpage)
        }
    }

    /// Rayon's groups on this page; on a terminal page they come first.
    var groups: [SettingsGroup] {
        SettingsGroup.allCases.filter { $0.page == self && $0.isAvailable }
    }
}

struct SettingsSection: Identifiable {
    let title: String?
    let pages: [SettingsPage]

    /// Not its first page's id: the Mac's sidebar takes a section whose
    /// identity equals the selection for selected too, and highlighted its
    /// header together with the first row.
    var id: String {
        "section:" + (pages.first?.id ?? "")
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
    case diagnostics
    case acknowledgements

    var id: String {
        rawValue
    }

    var page: SettingsPage {
        switch self {
        case .appearance, .sessions, .recent, .sync, .data: .general
        case .ssh, .uuRemote, .monitor: .connection
        case .terminalClipboard: SettingsPage(id: "input") ?? .general
        case .about, .diagnostics, .acknowledgements: .about
        }
    }

    var title: String {
        switch self {
        case .appearance: String(localized: "Appearance")
        case .sessions: String(localized: "Sessions")
        case .recent: String(localized: "Recent")
        case .sync: String(localized: "iCloud Sync")
        case .data: String(localized: "Data")
        case .ssh: String(localized: "SSH")
        case .uuRemote: String(localized: "NetEase UU Remote")
        case .monitor: String(localized: "Monitor")
        case .terminalClipboard: String(localized: "Copy on Select")
        case .about: String(localized: "Rayon")
        case .diagnostics: String(localized: "Diagnostics & Usage")
        case .acknowledgements: String(localized: "Acknowledgements")
        }
    }

    /// The words search finds the group by, besides its page and title.
    var keywords: String {
        switch self {
        case .appearance: "appearance dark light mode theme system effects animation background home glow gradient reduce motion"
        case .sessions: "open sessions automatically ask before closing confirmation quit"
        case .recent: "recent servers history quick connect commands record remember"
        case .sync: "icloud sync cloud servers identities snippets port forwards terminal settings credentials devices"
        case .data: "data container files log diagnostics backup export import restore ssh config openssh archive"
        case .ssh: "ssh timeout connect wait host key known hosts fingerprint terminfo ghostty"
        case .uuRemote: "uu remote netease remote desktop device account qr login"
        case .monitor: "monitor refresh interval status"
        case .terminalClipboard: "copy on select selection clipboard pasteboard automatically share remote osc52 programs"
        case .about: "version build license source github issues agreement"
        case .diagnostics: "diagnostics usage telemetry analytics crash reports privacy policy data sent anonymous"
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
        case .diagnostics: DiagnosticsSettings()
        case .acknowledgements: AcknowledgementSettings()
        }
    }
}

/// A group as a form section; `prefix` names its page in search results.
struct SettingsGroupSection: View {
    let group: SettingsGroup
    var prefix: String?

    var body: some View {
        Section(prefix.map { String(localized: "\($0) › \(group.title)") } ?? group.title) {
            group.rows
        }
    }
}
