//
//  RayonApp.swift
//  Rayon
//
//  The app's entry on every platform. What each platform installs at launch,
//  its window's root view and the Mac's app delegate are in RayonApp+macOS
//  and RayonApp+iOS.
//

import RayonModule
import SwiftUI

@main
struct RayonApp: App {
    @StateObject private var store = RayonStore.shared
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        #if DEBUG
            Logger.app.debugFile("command arguments: \(private: CommandLine.arguments.joined(separator: " "))")
        #endif
        Self.installPlatformHandlers()
        _ = RayonStore.shared
        CloudSyncModel.shared.start()
        Telemetry.shared.snapshot = { .rayon }
        Telemetry.shared.start(
            choice: AppSettings.telemetryLevel.value,
            noticeShown: AppSettings.telemetryNoticeShown.value
        ) { choice, noticeShown in
            AppSettings.telemetryLevel.set(choice)
            AppSettings.telemetryNoticeShown.set(noticeShown)
        }
        Logger.app.infoFile("launched")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Telemetry.shared.wake() }
                }
        }
        #if os(macOS)
        .windowToolbarStyle(.unified)
        #endif
        .commands {
            SidebarCommands()
            RayonCommands()
        }
    }
}
