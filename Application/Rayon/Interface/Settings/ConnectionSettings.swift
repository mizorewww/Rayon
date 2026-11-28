//
//  ConnectionSettings.swift
//  Rayon
//
//  Settings › Connection: SSH, the UU Remote account (Mac) and the monitor.
//

import RayonModule
import SwiftUI

struct SSHSettings: View {
    @AppSetting(AppSettings.connectionTimeout, title: "Connection timeout") private var timeout
    @AppSetting(AppSettings.installsTerminfo, title: "Install Ghostty's terminfo") private var installsTerminfo

    var body: some View {
        LabeledContent {
            // The value before the arrows, as the system's own steppers have it.
            HStack {
                Text("\(timeout) s").monospacedDigit()
                Stepper("Connection timeout", value: $timeout, in: 2 ... 30)
                    .labelsHidden()
            }
        } label: {
            Text("Connection timeout")
            Text("How long to wait for a server before giving up.")
        }
        Toggle(isOn: $installsTerminfo) {
            Text("Install Ghostty's terminfo")
            Text("Rayon's terminal is Ghostty. On a server that lacks its terminfo, Rayon adds it to ~/.terminfo once, so programs there use every feature; nothing else on the server changes. When off, or where it cannot be added, sessions run as xterm-256color.")
        }
        HostKeysRow()
    }
}

/// How many host keys are saved, and a way to start over.
private struct HostKeysRow: View {
    @State private var count = KnownHosts.shared.count

    var body: some View {
        LabeledContent {
            Button("Forget All…") {
                Indicator.confirm(
                    message: "Forget all saved host keys?",
                    informative: "The key each server presents on its next connection is saved as its key.",
                    confirmTitle: "Forget All",
                    destructive: true
                ) { confirmed in
                    guard confirmed else { return }
                    KnownHosts.shared.forgetAll()
                    count = KnownHosts.shared.count
                }
            }
            .disabled(count == 0)
        } label: {
            Text("Saved host keys")
            Text("A server's key is saved the first time you connect; a server that later presents another key is refused. \(count) saved.")
        }
        .onAppear { count = KnownHosts.shared.count }
    }
}

struct MonitorSettings: View {
    @AppSetting(AppSettings.monitorInterval, title: "Refresh") private var interval
    private let intervals = [5, 10, 15, 30, 60]

    var body: some View {
        Picker(selection: $interval) {
            ForEach(intervals, id: \.self) { Text("Every \($0) s").tag($0) }
            if !intervals.contains(interval) {
                Text("Every \(interval) s").tag(interval)
            }
        } label: {
            Text("Refresh")
            Text("How often an open monitor reads the server.")
        }
    }
}

#if os(macOS)
    /// The NetEase UU Remote account behind the remote desktop feature.
    struct UURemoteSettings: View {
        @ObservedObject private var account = UURemoteAccount.shared

        var body: some View {
            LabeledContent {
                HStack {
                    if account.isLoggedIn {
                        Label(account.nickname.isEmpty ? "Signed in" : account.nickname, systemImage: "person.crop.circle")
                            .lineLimit(1)
                        Button("Manage…") { openAccountSheet() }
                        Button("Sign Out") { account.logout() }
                    } else {
                        Text("Not signed in")
                            .foregroundStyle(.secondary)
                        Button("Sign In…") { openAccountSheet() }
                    }
                }
            } label: {
                Text("Account")
                Text("Signs the built-in UU Remote client in with QR code, SMS or an imported token.")
            }
            if account.isLoggedIn {
                LabeledContent {
                    HStack {
                        Text(UURemoteAccount.deviceCount(account.desktopDevices.count))
                            .foregroundStyle(.secondary)
                        Button("Refresh") {
                            Task { try? await account.refreshDevices() }
                        }
                    }
                } label: {
                    Text("Devices")
                    Text("Desktop devices on this account; add them as servers from the account panel.")
                }
            }
        }

        private func openAccountSheet() {
            AppRouter.shared.present { dismiss in
                UURemoteAccountSheet(onConnectDesktop: { machineID in
                    dismiss()
                    AppRouter.shared.openDesktop(machine: machineID)
                }, close: dismiss)
            }
        }
    }
#endif
