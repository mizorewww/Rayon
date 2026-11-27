//
//  AppSettings.swift
//  RayonModule
//
//  Every setting Rayon has, by key. The terminal's own settings are not
//  here: they live in config.ghostty (RayonTerminal's TerminalSettings).
//

import Foundation
import Telemetry

public enum AppSettings {
    // MARK: Appearance

    public static let appearance = SettingKey("appearance.mode", default: Appearance.system, scope: .synced)
    /// The moving background behind Quick Connect.
    public static let animatesHome = SettingKey("appearance.animatesHome", default: true, scope: .synced)

    // MARK: Sessions

    /// Switch to a session's page as soon as it connects.
    public static let showsSessionOnConnect = SettingKey("sessions.showOnConnect", default: true, scope: .synced)
    /// Ask before closing a connected session or quitting.
    public static let confirmsClosingSession = SettingKey("sessions.confirmClose", default: true, scope: .synced)

    // MARK: Recent

    public static let remembersRecent = SettingKey("recent.enabled", default: true, scope: .synced)
    public static let recentLimit = SettingKey("recent.limit", default: 8, scope: .synced)
    /// Quick Connect commands are remembered with the servers.
    public static let remembersRecentCommands = SettingKey("recent.includesCommands", default: true, scope: .synced)

    // MARK: Connection

    /// Seconds to wait for a server.
    public static let connectionTimeout = SettingKey("connection.timeout", default: 5, scope: .synced)
    public static let installsTerminfo = SettingKey("connection.installsTerminfo", default: true, scope: .synced)
    /// Seconds between two reads of an open monitor.
    public static let monitorInterval = SettingKey("monitor.interval", default: 5, scope: .synced)

    // MARK: Servers

    public static let serverRedaction = SettingKey("servers.redaction", default: RDMachine.RedactedLevel.none, scope: .synced)

    // MARK: Terminal

    /// The size a session starts at, and that ⌘+ and ⌘− change; it fits the
    /// screen, so it stays on the device.
    public static let terminalFontSize = SettingKey("terminal.fontSize", default: 14, scope: .device)
    public static let terminalCopiesOnSelect = SettingKey("terminal.copyOnSelect", default: true, scope: .synced)
    /// Programs on the server may read and write the clipboard (OSC 52).
    public static let terminalSharesClipboard = SettingKey("terminal.clipboardSharing", default: true, scope: .synced)

    // MARK: Editor

    public static let editorWrapsLines = SettingKey("editor.wrapsLines", default: false, scope: .synced)

    // MARK: Remote desktop

    /// About the hand, not the server: one for every desktop on the device.
    public static let remoteDesktopTouchMode = SettingKey("remoteDesktop.touchMode", default: RemoteDesktopTouchMode.trackpad, scope: .device)
    /// How many times the touch gestures were explained.
    public static let remoteDesktopGestureHintsShown = SettingKey("remoteDesktop.gestureHintsShown", default: 0, scope: .deviceLocal)

    // MARK: UU Remote

    /// The UU device ids Rayon signed in as, from every device: the service
    /// lists each sign-in as a Windows host, which Rayon does not show.
    public static let uuRemoteSignIns = SettingKey("uuRemote.signIns", default: [String](), scope: .synced)
    /// UU devices whose server the person deleted. They stay on the account,
    /// which Rayon cannot remove a device from, and Rayon no longer lists them.
    public static let uuRemoteRemovedDevices = SettingKey("uuRemote.removedDevices", default: [String](), scope: .synced)

    // MARK: Menu bar

    /// The servers shown in the Mac's menu bar.
    public static let menuBarServers = SettingKey("menuBar.servers", default: [RDMachine.ID](), scope: .deviceLocal)

    // MARK: iCloud sync

    /// Each device chooses for itself whether, and what, it syncs.
    public static let syncEnabled = SettingKey("sync.enabled", default: false, scope: .deviceLocal)
    public static let syncsServers = SettingKey("sync.servers", default: true, scope: .deviceLocal)
    public static let syncsIdentities = SettingKey("sync.identities", default: true, scope: .deviceLocal)
    public static let syncsSnippets = SettingKey("sync.snippets", default: true, scope: .deviceLocal)
    public static let syncsPortForwards = SettingKey("sync.portForwards", default: true, scope: .deviceLocal)
    public static let syncsTerminalSettings = SettingKey("sync.terminalSettings", default: true, scope: .deviceLocal)
    public static let syncsAppSettings = SettingKey("sync.appSettings", default: true, scope: .deviceLocal)

    // MARK: Diagnostics & usage

    /// The telemetry level this device chose; nil until a choice. Consent
    /// belongs to the device and the storefront it was given in.
    public static let telemetryLevel = SettingKey("telemetry.level", default: TelemetryLevel?.none, scope: .deviceLocal)
    /// The one-time notice on Home was answered.
    public static let telemetryNoticeShown = SettingKey("telemetry.noticeShown", default: false, scope: .deviceLocal)

    public static let all: [any AnySettingKey] = [
        appearance, animatesHome,
        showsSessionOnConnect, confirmsClosingSession,
        remembersRecent, recentLimit, remembersRecentCommands,
        connectionTimeout, installsTerminfo, monitorInterval,
        serverRedaction,
        terminalFontSize, terminalCopiesOnSelect, terminalSharesClipboard,
        editorWrapsLines,
        remoteDesktopTouchMode, remoteDesktopGestureHintsShown,
        uuRemoteSignIns, uuRemoteRemovedDevices,
        menuBarServers,
        syncEnabled, syncsServers, syncsIdentities, syncsSnippets, syncsPortForwards, syncsTerminalSettings, syncsAppSettings,
        telemetryLevel, telemetryNoticeShown,
    ]

    /// The keys iCloud carries.
    public static let syncedKeys: Set<String> = Set(all.filter { $0.scope == .synced }.map(\.key))
}

/// Light or dark, or as the system is.
public enum Appearance: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var title: String {
        switch self {
        case .system: String(localized: "System", bundle: .module)
        case .light: String(localized: "Light", bundle: .module)
        case .dark: String(localized: "Dark", bundle: .module)
        }
    }
}
