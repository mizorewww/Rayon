//
//  SettingView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/2.
//

import RayonModule
import SwiftUI

struct SettingView: View {
    @StateObject var store = RayonStore.shared
    @AppStorage("wiki.qaq.rayon.maxRecentRecordCount") private var recentLimit = 8

    #if DEBUG
        @State var redirectLog = false
    #endif

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(get: { !store.disableConformation }, set: { store.disableConformation = !$0 })) {
                    row("Ask before closing", "Confirm before closing sessions or deleting items.")
                }
                Toggle(isOn: $store.storeRecent) {
                    row("Remember recent servers", "Shows recent servers and commands on Home.")
                }
                Stepper(value: $recentLimit, in: 1 ... 50) {
                    row("Recent items to keep", "\(recentLimit)")
                }
                .disabled(!store.storeRecent)
                Toggle(isOn: $store.saveTemporarySession) {
                    row("Record Quick Connect commands", "Lets Quick Connect suggest them.")
                }
                Toggle(isOn: $store.openInterfaceAutomatically) {
                    row("Open sessions when connected", "Show a terminal or file transfer as soon as it opens.")
                }
            } header: {
                RXSectionHeader("Behavior")
            }
            .rxListRow()

            Section {
                Stepper(value: $store.timeout, in: 2 ... 30) {
                    row("SSH timeout", "\(store.timeout) s")
                }
                Stepper(value: $store.monitorInterval, in: 5 ... 60, step: 5) {
                    row("Monitor refresh", "\(store.monitorInterval) s")
                }
                Stepper(value: $store.terminalFontSize, in: 5 ... 30) {
                    row("Terminal font size", "\(store.terminalFontSize) pt")
                }
            } header: {
                RXSectionHeader("Connection")
            }
            .rxListRow()

            Section {
                Button {
                    UIBridge.openFileContainer()
                } label: {
                    Label("Show App Container", systemImage: "folder")
                }
                NavigationLink {
                    LogView()
                } label: {
                    Label("App Log", systemImage: "doc.text.magnifyingglass")
                }
                #if DEBUG
                    Toggle("Redirect log", isOn: $redirectLog)
                        .onChange(of: redirectLog) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "wiki.qaq.redirect.diag")
                        }
                        .onAppear {
                            redirectLog = UserDefaults.standard.value(forKey: "wiki.qaq.redirect.diag") as? Bool ?? false
                        }
                #endif
            } header: {
                RXSectionHeader("Data")
            } footer: {
                Text("Log redirection takes effect after restarting the app.")
            }
            .rxListRow()

            Section {
                Link(destination: URL(string: "https://github.com/Lakr233/Rayon")!) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                NavigationLink {
                    LicenseView()
                } label: {
                    Label("License", systemImage: "doc.text")
                }
            } header: {
                RXSectionHeader("About")
            } footer: {
                Text(appVersion)
            }
            .rxListRow()
        }
        .rxGroupedList()
        .navigationTitle("Settings")
        .onChange(of: recentLimit) { limit in
            store.maxRecentRecordCount = limit
            if store.recentRecord.count > limit {
                store.recentRecord = Array(store.recentRecord.prefix(limit))
            }
        }
    }

    func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.rxInk)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.rxInkSecondary)
        }
    }
}
