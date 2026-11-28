//
//  GeneralSettings.swift
//  Rayon
//
//  Settings › General: appearance, sessions, recent servers and iCloud sync.
//  The Data group is each platform's own (DataSettings).
//

import RayonModule
import SwiftUI

struct AppearanceSettings: View {
    @AppSetting(AppSettings.appearance, title: "Light or dark") private var appearance
    @AppSetting(AppSettings.animatesHome, title: "Animate Home") private var animatesHome

    var body: some View {
        Picker(selection: $appearance) {
            ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
        } label: {
            Text("Light or dark")
            Text("Terminal colors are set under Colors.")
        }
        #if os(macOS)
        .pickerStyle(.segmented)
        #endif
        Toggle(isOn: $animatesHome) {
            Text("Animate Home")
            Text("The moving background behind Quick Connect.")
        }
    }
}

struct SessionSettings: View {
    @AppSetting(AppSettings.showsSessionOnConnect, title: "Show a session when it connects") private var showsOnConnect
    @AppSetting(AppSettings.confirmsClosingSession, title: "Ask before closing a session") private var confirmsClose

    var body: some View {
        Toggle(isOn: $showsOnConnect) {
            Text("Show a session when it connects")
            #if os(macOS)
                Text("Switch to a terminal as soon as it opens.")
            #else
                Text("Open the terminal as soon as it connects.")
            #endif
        }
        Toggle(isOn: $confirmsClose) {
            Text("Ask before closing a session")
            #if os(macOS)
                Text("Confirm before closing a connected terminal or quitting.")
            #else
                Text("Confirm before closing a connected terminal.")
            #endif
        }
    }
}

struct RecentSettings: View {
    @AppSetting(AppSettings.remembersRecent, title: "Remember recent servers") private var remembersRecent
    @AppSetting(AppSettings.recentLimit, title: "Number to keep") private var recentLimit
    @AppSetting(AppSettings.remembersRecentCommands, title: "Include Quick Connect commands") private var remembersCommands

    var body: some View {
        Toggle(isOn: $remembersRecent) {
            Text("Remember recent servers")
            Text("Listed under Quick Connect on Home.")
        }
        LabeledContent("Number to keep") {
            // The value before the arrows, as the system's own steppers have it.
            HStack {
                Text(recentLimit, format: .number).monospacedDigit()
                Stepper("Number to keep", value: $recentLimit, in: 1 ... 50)
                    .labelsHidden()
            }
        }
        .disabled(!remembersRecent)
        Toggle(isOn: $remembersCommands) {
            Text("Include Quick Connect commands")
            Text("Also remember user@host commands typed on Home.")
        }
        .disabled(!remembersRecent)
    }
}

/// iCloud sync: on or off, and which kinds of records go.
struct CloudSyncSettings: View {
    @ObservedObject private var sync = CloudSyncModel.shared
    @State private var confirmingDelete = false
    @State private var deleting = false

    var body: some View {
        Toggle(isOn: $sync.preferences.isOn) {
            Text("Sync with iCloud")
            Text(sync.preferences.isOn ? "\(sync.statusText)" : "Keep your data the same on every device signed in to your iCloud account. Passwords and keys travel end-to-end encrypted.")
        }
        if sync.preferences.isOn, sync.status == .accountChanged {
            LabeledContent {
                Button("Sync with This Account") { sync.resumeWithCurrentAccount() }
            } label: {
                Text("iCloud account")
                Text("Merge this device's servers, identities and settings with the account signed in now, and send them to it. Or turn sync off to keep them here only.")
            }
        } else if sync.preferences.isOn, sync.status != .unavailable {
            LabeledContent {
                Button("Sync Now") { sync.syncNow() }
                    .disabled(!sync.canSyncNow)
            } label: {
                Text("Sync now")
                Text("Fetch and send changes without waiting.")
            }
        }
        Group {
            Toggle(isOn: $sync.preferences.servers) {
                Text("Servers")
                Text("With their folders.")
            }
            Toggle(isOn: $sync.preferences.identities) {
                Text("Identities")
                Text("Including passwords and private keys.")
            }
            Toggle("Snippets", isOn: $sync.preferences.snippets)
            Toggle("Port forwards", isOn: $sync.preferences.portForwards)
            Toggle(isOn: $sync.preferences.terminalSettings) {
                Text("Terminal settings")
                Text("Theme, colors, fonts and shortcuts. Font size and padding stay on each device.")
            }
            Toggle(isOn: $sync.preferences.appSettings) {
                Text("Settings")
                Text("Appearance, sessions, recent servers, timeouts, monitor and terminal behavior. Font size, touch mode and the menu bar stay on each device.")
            }
        }
        .disabled(!sync.preferences.isOn)
        if CloudSync.isAvailable {
            LabeledContent {
                Button("Delete…") { confirmingDelete = true }
                    .disabled(deleting)
            } label: {
                Text("Data in iCloud")
                Text("Remove it and stop syncing on this device.")
            }
            .alert("Delete what Rayon keeps in iCloud?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) {
                    deleting = true
                    Task {
                        if let problem = await sync.deleteCloudData() {
                            Indicator.error(String(localized: "Could not delete the data in iCloud: \(problem)"))
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
}
