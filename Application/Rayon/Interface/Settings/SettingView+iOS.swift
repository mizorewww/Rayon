//
//  SettingView+iOS.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/3/2.
//
//  Settings is the shared RayonTerminal layout (the same categories and order as
//  on macOS: General, Connection, then the terminal, then About); this file
//  supplies the rows for Rayon's own preferences on iOS.
//

#if os(iOS)
    import RayonModule
    import RayonTerminal
    import SwiftUI

    struct SettingView: View {
        @ObservedObject var store = RayonStore.shared

        var body: some View {
            GhosttyConfigurationView(
                hostSections: [
                    ConfigHostSettingsSection(id: "general.appearance", keywords: "appearance dark light mode theme system effects animation background home glow reduce motion") {
                        AppearanceSettings()
                    },
                    ConfigHostSettingsSection(id: "general.sessions", keywords: "open sessions automatically ask before closing confirmation") {
                        SessionSettings()
                    },
                    ConfigHostSettingsSection(id: "general.recent", keywords: "recent servers history quick connect commands record remember") {
                        RecentSettings()
                    },
                    ConfigHostSettingsSection(id: "general.sync", keywords: "icloud sync cloud servers identities snippets port forwards terminal settings credentials devices") {
                        CloudSyncSettings()
                    },
                    ConfigHostSettingsSection(id: "general.data", keywords: "data container files log diagnostics backup export import restore ssh config openssh archive") {
                        DataSettings()
                    },
                    ConfigHostSettingsSection(id: "connection.ssh", keywords: "ssh timeout connect wait host key known hosts fingerprint") {
                        SSHSettings()
                    },
                    ConfigHostSettingsSection(id: "connection.monitor", keywords: "monitor refresh interval status") {
                        MonitorSettings()
                    },
                    ConfigHostSettingsSection(id: "terminal.copyOnSelect", keywords: "copy on select selection clipboard pasteboard automatically share remote osc52 programs") {
                        CopyOnSelectSettings()
                    },
                    ConfigHostSettingsSection(id: "about.Rayon", keywords: "version build license source github issues") {
                        AboutSettings()
                    },
                    ConfigHostSettingsSection(id: "about.acknowledgements", keywords: "acknowledgements credits libraries ghostty") {
                        AcknowledgementSettings()
                    },
                ],
                onApplied: { size in
                    // One font size: the terminal's Size setting also sets the size
                    // new sessions start from.
                    if let size { AppSettings.terminalFontSize.set(Int(size.rounded())) }
                }
            )
        }
    }

    private struct AppearanceSettings: View {
        @AppSetting(AppSettings.appearance) private var appearance
        @AppSetting(AppSettings.animatesHome) private var animatesHome

        var body: some View {
            RXDividedStack {
                RXFormRow("Light or dark", description: "Terminal colors are set under Colors.") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SwitchRow(
                    "Animate Home",
                    description: "A soft glow and drifting dots behind Quick Connect.",
                    isOn: $animatesHome
                )
            }
        }
    }

    private struct SessionSettings: View {
        @AppSetting(AppSettings.showsSessionOnConnect) private var showsOnConnect
        @AppSetting(AppSettings.confirmsClosingSession) private var confirmsClose

        var body: some View {
            RXDividedStack {
                SwitchRow(
                    "Show a session when it connects",
                    description: "Open the terminal as soon as it connects.",
                    isOn: $showsOnConnect
                )
                SwitchRow(
                    "Ask before closing a session",
                    description: "Confirm before closing a connected terminal.",
                    isOn: $confirmsClose
                )
            }
        }
    }

    private struct RecentSettings: View {
        @AppSetting(AppSettings.remembersRecent) private var remembersRecent
        @AppSetting(AppSettings.recentLimit) private var recentLimit
        @AppSetting(AppSettings.remembersRecentCommands) private var remembersCommands

        var body: some View {
            RXDividedStack {
                SwitchRow("Remember recent servers", description: "Listed under Quick Connect on Home.", isOn: $remembersRecent)
                NumberFieldRow("Number to keep", value: $recentLimit, in: 1 ... 50)
                    .disabled(!remembersRecent)
                SwitchRow(
                    "Include Quick Connect commands",
                    description: "Also remember user@host commands typed on Home.",
                    isOn: $remembersCommands
                )
                .disabled(!remembersRecent)
            }
        }
    }

    private struct DataSettings: View {
        #if DEBUG
            @State private var redirectLog = UserDefaults.standard.value(forKey: "me.mizorewww.redirect.diag") as? Bool ?? false
        #endif

        var body: some View {
            RXDividedStack {
                DataBackupRows()
                RXFormRow("App container", description: "Files the app keeps, in the Files app.") {
                    Button("Show") { UIBridge.openFileContainer() }
                        .buttonStyle(.rx(size: .small))
                }
                NavigationLink {
                    LogView()
                } label: {
                    RXFormRow("App log", description: "Diagnostics for reporting a problem.") {
                        Image(systemName: "chevron.right").foregroundStyle(.rxInkTertiary)
                    }
                }
                .buttonStyle(.plain)
                #if DEBUG
                    SwitchRow(
                        "Redirect log",
                        description: "Takes effect after restarting the app.",
                        isOn: $redirectLog
                    )
                    .onChange(of: redirectLog) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "me.mizorewww.redirect.diag")
                    }
                #endif
            }
        }
    }

    private struct SSHSettings: View {
        @AppSetting(AppSettings.connectionTimeout) private var timeout

        var body: some View {
            RXDividedStack {
                NumberFieldRow(
                    "Connection timeout",
                    description: "How long to wait for a server before giving up.",
                    value: $timeout,
                    in: 2 ... 30,
                    unit: "s"
                )
                HostKeysRow()
            }
        }
    }

    /// How many host keys are saved, and a way to start over.
    private struct HostKeysRow: View {
        @State private var count = KnownHosts.shared.count

        var body: some View {
            RXFormRow(
                "Saved host keys",
                description: "A server's key is saved the first time you connect; a server that later presents another key is refused. \(count) saved."
            ) {
                Button("Forget All…") {
                    UIBridge.requiresConfirmation(message: "Forget all saved host keys?") { confirmed in
                        guard confirmed else { return }
                        KnownHosts.shared.forgetAll()
                        count = KnownHosts.shared.count
                    }
                }
                .buttonStyle(.rx(size: .small))
                .disabled(count == 0)
            }
            .onAppear { count = KnownHosts.shared.count }
        }
    }

    private struct MonitorSettings: View {
        @AppSetting(AppSettings.monitorInterval) private var interval
        private let intervals = [5, 10, 15, 30, 60]

        var body: some View {
            RXFormRow("Refresh", description: "How often an open monitor reads the server.") {
                Picker("Refresh", selection: $interval) {
                    ForEach(intervals, id: \.self) { Text("Every \($0) s").tag($0) }
                    if !intervals.contains(interval) {
                        Text("Every \(interval) s").tag(interval)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    /// Terminal, Mouse & Clipboard: the row above Ghostty's copy settings.
    private struct CopyOnSelectSettings: View {
        @AppSetting(AppSettings.terminalCopiesOnSelect) private var copiesOnSelect
        @AppSetting(AppSettings.terminalSharesClipboard) private var sharesClipboard

        var body: some View {
            RXDividedStack {
                SwitchRow(
                    "Copy on select",
                    description: "Copy text to the clipboard as soon as you finish selecting it.",
                    isOn: $copiesOnSelect
                )
                SwitchRow(
                    "Share clipboard with remote programs",
                    description: "Programs running on the server may read and write this device's clipboard (OSC 52), so a copy in vim or tmux lands here.",
                    isOn: $sharesClipboard
                )
            }
        }
    }

    private struct AboutSettings: View {
        var body: some View {
            RXDividedStack {
                RXFormRow("Version") {
                    Text(appVersion)
                        .font(.rxBody.monospacedDigit())
                        .foregroundStyle(.rxInkSecondary)
                }
                RXFormRow("Source code", description: "mizorewww/Rayon on GitHub") {
                    Link("GitHub", destination: URL(string: "https://github.com/mizorewww/Rayon")!)
                }
                RXFormRow("Report a problem") {
                    Link("Issues", destination: URL(string: "https://github.com/mizorewww/Rayon/issues")!)
                }
                NavigationLink {
                    LicenseView()
                } label: {
                    RXFormRow("License") {
                        Image(systemName: "chevron.right").foregroundStyle(.rxInkTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private struct AcknowledgementSettings: View {
        var body: some View {
            RXDividedStack {
                RXFormRow("Maintained by", description: "mizorewww") {
                    EmptyView()
                }
                RXFormRow("Originally created by", description: "Lakr Aream (@Lakr233) with @__oquery, @zlind0, @unixzii, @82flex and @xnth97. This version is not affiliated with or endorsed by them.") {
                    EmptyView()
                }
                RXFormRow("Terminal", description: "Ghostty and its configuration catalog (MIT, Ghostty contributors).") {
                    EmptyView()
                }
                RXFormRow("Libraries", description: LicenseNotices.bundledLibraries.joined(separator: " · ")) {
                    EmptyView()
                }
            }
        }
    }

    /// iCloud sync: on or off, and which kinds of records go.
    private struct CloudSyncSettings: View {
        @ObservedObject var sync = CloudSyncModel.shared
        @State private var confirmingDelete = false
        @State private var deleting = false

        var body: some View {
            RXDividedStack {
                SwitchRow(
                    "Sync with iCloud",
                    description: sync.preferences.isOn ? sync.statusText : "Keep your data the same on every device signed in to your iCloud account. Passwords and keys travel end-to-end encrypted.",
                    isOn: $sync.preferences.isOn
                )
                if sync.preferences.isOn, sync.status != .unavailable {
                    RXFormRow("Sync now", description: "Fetch and send changes without waiting.") {
                        Button("Sync Now") { sync.syncNow() }
                            .buttonStyle(.rx(size: .small))
                            .disabled(!sync.canSyncNow)
                    }
                }
                Group {
                    SwitchRow("Servers", description: "With their folders.", isOn: $sync.preferences.servers)
                    SwitchRow("Identities", description: "Including passwords and private keys.", isOn: $sync.preferences.identities)
                    SwitchRow("Snippets", isOn: $sync.preferences.snippets)
                    SwitchRow("Port forwards", isOn: $sync.preferences.portForwards)
                    SwitchRow("Terminal settings", description: "Theme, colors, fonts and shortcuts. Font size and padding stay on each device.", isOn: $sync.preferences.terminalSettings)
                    SwitchRow("Settings", description: "Appearance, sessions, recent servers, timeouts, monitor and terminal behavior.", isOn: $sync.preferences.appSettings)
                }
                .disabled(!sync.preferences.isOn)
                if CloudSync.isAvailable {
                    RXFormRow("Data in iCloud", description: "Remove it and stop syncing on this device.") {
                        Button("Delete…") { confirmingDelete = true }
                            .buttonStyle(.rx(size: .small))
                            .disabled(deleting)
                    }
                }
            }
            .alert("Delete what Rayon keeps in iCloud?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) {
                    deleting = true
                    Task {
                        if let problem = await sync.deleteCloudData() {
                            UIBridge.presentError(with: "Could not delete the data in iCloud: \(problem)")
                        }
                        deleting = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your data stays on this device. A device that still syncs will store its own again, so turn sync off there too.")
            }
        }
    }

#endif
